import DLCore
import Foundation
import Observation

/// A Meshtastic LoRa radio as one more way to carry DLChat's sealed messages, off by default. When
/// on and paired, Chat sends each message to the radio as a private-app broadcast on its primary
/// channel, and anything the radio hears that opens with one of this phone's groups is stored like
/// any other message. Never sends while the radio is in licensed (ham) mode, where encryption is not allowed.
///
/// Setup on pairing, so the Meshtastic app is not needed: a radio with no region gets one from the phone's
/// country, after the person confirms (a wrong region is illegal to transmit on); location sharing is turned
/// off on its own (GPS off, no fixed position, primary channel shares no position).
@MainActor
@Observable
final class MeshtasticModel {
    enum Status: Equatable {
        case off, bluetoothOff, unauthorized, searching, connecting, ready, disconnected
        /// Another app on this iPhone (usually the Meshtastic app) holds the radio; DLChat waits for it.
        case busy
        /// DLChat let go of the radio so another app can use it: on request, or while DLChat is in the background.
        case released
    }

    private(set) var isOn: Bool
    private(set) var status: Status = .off
    /// The Bluetooth side is running. False while the radio is on by default but still waiting for a first
    /// group (or a tap in Settings), so Settings can show the switch as it really is.
    private(set) var isRunning = false
    /// What Settings and the radio screens show as "on": switched on and actually running.
    var isActive: Bool { isOn && isRunning }
    private(set) var radios: [RadioLinkRadio] = []
    /// The paired radio's name, once it has said it.
    private(set) var radioName: String?
    /// The radio is set to licensed (ham) mode: DLChat will not send through it.
    private(set) var licensed = false
    private(set) var problem: String?
    /// The radio said it has no LoRa region, so it cannot transmit yet. False until its settings arrive.
    private(set) var regionUnset = false
    /// What DLChat did about the radio's location sharing, to show in Settings.
    private(set) var locationNote: String?
    /// A setting change was sent and the radio is applying it (it may restart).
    private(set) var applying = false
    /// Other radios this radio has heard, for the Mesh Map. Memory only; cleared on forget and wipe.
    private(set) var nodes: [UInt32: MeshNode] = [:]
    static let maxNodes = 1000
    /// Sealed packets remembered so a repeat from another hop is not handled twice.
    static let maxSeen = 2000
    /// A Meshtastic radio has 8 channels (index 0 to 7).
    static let maxChannels: UInt32 = 8

    // MARK: Meshtastic chats (plain Meshtastic text, not sealed with a DLChat phrase)

    /// The radio's channels in use (primary first), for the Meshtastic section of Manage groups.
    private(set) var channels: [Meshtastic.ChannelInfo] = []
    /// The modem preset's name ("LongFast"), which Meshtastic apps use as a default primary channel's name.
    private(set) var presetName: String?
    /// Text messages by conversation and hourly channel counts. Memory only by default: gone when the app
    /// closes, on forget and on wipe. Kept longer only when the person picks a period (`setKeep`), and then
    /// only in the sealed Vault store, which Wipe erases.
    private(set) var archive = MeshArchive()
    var texts: [MeshConversation: [MeshText]] { archive.texts }
    /// How long Meshtastic chats are kept. `.off`: until DLChat closes (the default).
    var keep: Retention { archive.keep }
    private(set) var unread: [MeshConversation: Int] = [:]
    /// The Meshtastic conversation Chat shows instead of the active group's chat; nil for the group.
    var open: MeshConversation?
    /// Chat is on screen showing `open`, so messages there count as read.
    var viewing = false

    /// Every private-app payload the radio hears; RootView hands it to `OnlineModel.store(wire:)`.
    @ObservationIgnored var onWire: ((Data) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeLink: () -> RadioLink
    @ObservationIgnored private var link: RadioLink?
    @ObservationIgnored private var myNode: UInt32?
    @ObservationIgnored private var configID: UInt32 = 0
    @ObservationIgnored private var seen: Set<Data> = []
    /// (from, packet id) of text messages already shown: the mesh repeats packets.
    @ObservationIgnored private var seenTexts: Set<UInt64> = []
    @ObservationIgnored private var archiveStore: MeshArchiveStore?
    /// False until the saved archive has been read (it cannot be while the iPhone is locked); nothing is
    /// saved before then, so a failed read never overwrites what was kept.
    @ObservationIgnored private var archiveLoaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var loraRaw: Data?
    @ObservationIgnored private var positionRaw: Data?
    @ObservationIgnored private var positionShares = false
    @ObservationIgnored private var primaryChannel: (raw: Data, precision: UInt64)?
    /// Location fix tried once per connection run, so a radio that refuses it is reported, not looped on.
    @ObservationIgnored private var locationTried = false
    @ObservationIgnored private let country: () -> String?
    /// How long to listen before picking a radio, so the nearest of several can be heard first.
    @ObservationIgnored private let pickDelay: Duration
    @ObservationIgnored private var pickTask: Task<Void, Never>?
    /// A radio picked on its own that has not finished connecting; passed over if it never does.
    @ObservationIgnored private var pickWatch: Task<Void, Never>?
    @ObservationIgnored private let pickTimeout: Duration
    /// Radios not to pick on their own again this run: forgotten, or never finished connecting
    /// (another person's radio, or its PIN was not entered).
    @ObservationIgnored private var passedOver: Set<UUID> = []
    /// The radio DLChat picked on its own, while it is still connecting (for Settings to explain the PIN).
    private(set) var autoPicked: UUID?
    /// Bumped when `isMine` changes, so screens redraw (it lives in UserDefaults).
    private(set) var mineVersion = 0

    /// The person tapped "Let go of radio": stays let go until they tap "Use radio here" or pick a radio.
    private(set) var letGoByHand = false
    /// Let go of the radio while DLChat is in the background, so the Meshtastic app can use it.
    private(set) var letsGoInBackground: Bool
    /// Let go because DLChat went to the background; taken back when it returns.
    @ObservationIgnored private var letGoForBackground = false

    static let onKey = "mesh.on", radioKey = "mesh.radio", backgroundKey = "mesh.letGoInBackground"
    /// The person accepted the radio rules notice ("I know the radio laws and I am responsible").
    /// The radio never starts without it, including for anyone who had it on from an older build.
    static let lawAcceptedKey = "mesh.lawAccepted"

    /// Whether the person has accepted responsibility for following the radio laws where they are.
    var lawAccepted: Bool { defaults.bool(forKey: Self.lawAcceptedKey) }

    /// Recorded when the person taps "I accept" on the radio rules notice, before turning the radio on.
    func acceptLaw() { defaults.set(true, forKey: Self.lawAcceptedKey) }
    /// The saved radio was picked on its own and the person has not yet said it is theirs.
    static let unconfirmedKey = "mesh.radio.unconfirmed"

    /// The saved radio is the person's own: chosen by hand, or confirmed after DLChat picked it.
    /// Until then DLChat changes nothing on it (location, region): it may be a stranger's radio
    /// with a fixed or no PIN.
    var isMine: Bool {
        guard let saved = savedRadio else { return false }
        return defaults.string(forKey: Self.unconfirmedKey) != saved.uuidString
    }

    /// "This is my radio": DLChat may now turn off its location sharing and offer to set its region.
    func confirmMine() {
        defaults.removeObject(forKey: Self.unconfirmedKey)
        mineVersion += 1
        if status == .ready { turnOffLocationIfNeeded() }
    }

    init(defaults: UserDefaults = .standard, country: @escaping () -> String? = { Locale.current.region?.identifier },
         pickDelay: Duration = .seconds(3), pickTimeout: Duration = .seconds(90), saveDelay: Duration = .seconds(5),
         makeLink: (() -> RadioLink)? = nil) {
        self.defaults = defaults
        self.saveDelay = saveDelay
        self.country = country
        self.pickDelay = pickDelay
        self.pickTimeout = pickTimeout
        self.makeLink = makeLink ?? { MeshtasticLink() }
        letsGoInBackground = defaults.object(forKey: Self.backgroundKey) as? Bool ?? true
        // Off until the person turns it on and accepts the radio rules (owner decision 2026-11-12, replaces
        // on-by-default from 2026-11-08). Once on, DLChat keeps reconnecting to the chosen radio.
        let chosen = defaults.object(forKey: Self.onKey) != nil
        isOn = chosen && defaults.bool(forKey: Self.onKey) && defaults.bool(forKey: Self.lawAcceptedKey)
        // A default (never-touched) setting waits for `startIfWanted()`, so iOS asks for Bluetooth after setup, not at first launch.
        if isOn && chosen { start() }
    }

    var savedRadio: UUID? { defaults.string(forKey: Self.radioKey).flatMap(UUID.init(uuidString:)) }
    var isReady: Bool { status == .ready && !licensed && !regionUnset }

    /// The region DLChat would set from the phone's country, or nil when it will not guess.
    var suggestedRegion: (code: UInt64, name: String)? { country().flatMap(Meshtastic.region(forCountry:)) }

    /// Sets the suggested region on a radio that has none. The radio restarts to apply it.
    func setSuggestedRegion() {
        guard isMine, regionUnset, let node = myNode, let raw = loraRaw, let region = suggestedRegion else { return }
        applying = true
        link?.write(Meshtastic.adminPacket(Meshtastic.setRegion(region.code, currentLoRa: raw), to: node, id: Self.packetID()))
        askForConfig()
    }

    /// Starts the radio if it is on and not running yet. RootView calls it once a group exists.
    func startIfWanted() { if isOn { start() } }

    /// Turning it on needs the radio rules accepted first (`acceptLaw()`); Settings asks before calling this.
    func setOn(_ on: Bool) {
        guard !on || lawAccepted else { return }
        isOn = on
        defaults.set(on, forKey: Self.onKey)
        if on { start() } else { stop() }
    }

    func setLetsGoInBackground(_ on: Bool) {
        letsGoInBackground = on
        defaults.set(on, forKey: Self.backgroundKey)
    }

    // MARK: Sharing the radio with other apps

    /// A radio serves one app at a time. Lets go cleanly (the radio is told first) so the Meshtastic
    /// app, or anything else, can connect, and stays let go until `useHere()`.
    func letGo() {
        guard isOn, savedRadio != nil else { return }
        letGoByHand = true
        release()
    }

    /// Takes the radio back after `letGo()`, or while it is busy. `evenIfBusy` connects although another
    /// app on this iPhone holds it; both then share it, and each may miss some messages.
    func useHere(evenIfBusy: Bool = false) {
        guard isOn, let saved = savedRadio else { return }
        letGoByHand = false
        letGoForBackground = false
        status = .connecting
        link?.connect(saved, evenIfBusy: evenIfBusy)
    }

    /// RootView reports when DLChat enters or leaves the background.
    func setForeground(_ active: Bool) {
        if active {
            guard letGoForBackground else { return }
            letGoForBackground = false
            if !letGoByHand { useHere() }
        } else {
            guard letsGoInBackground, isOn, savedRadio != nil, !letGoByHand, status != .released else { return }
            letGoForBackground = true
            release()
        }
    }

    private func release() {
        link?.disconnect()
        status = .released
        problem = nil
        resetSettings()  // read fresh when taken back; another app may have changed them
    }

    func choose(_ radio: RadioLinkRadio) { connect(to: radio, picked: false) }

    private func connect(to radio: RadioLinkRadio, picked: Bool) {
        letGoByHand = false
        letGoForBackground = false
        if status == .released { status = .connecting }
        pickTask?.cancel(); pickTask = nil
        pickWatch?.cancel(); pickWatch = nil
        if let current = savedRadio, current != radio.id { link?.disconnect(); resetSettings(); myNode = nil; licensed = false }
        autoPicked = picked ? radio.id : nil
        if picked {
            pickWatch = Task { [weak self, pickTimeout] in
                try? await Task.sleep(for: pickTimeout)
                guard let self, !Task.isCancelled, self.autoPicked == radio.id else { return }
                self.passOver(radio.id)
            }
        }
        defaults.set(radio.id.uuidString, forKey: Self.radioKey)
        if picked { defaults.set(radio.id.uuidString, forKey: Self.unconfirmedKey) } else { defaults.removeObject(forKey: Self.unconfirmedKey) }
        mineVersion += 1
        radioName = radio.name
        link?.connect(radio.id)
    }

    /// No radio chosen yet: after a short listen, connect to the strongest radio found, with no button to press.
    /// iOS may still ask for the radio's PIN the first time; a radio that never finishes connecting
    /// (someone else's, or a PIN not entered) is passed over for the next one.
    private func pickIfNeeded() {
        guard isOn, savedRadio == nil, pickTask == nil else { return }
        pickTask = Task { [weak self, pickDelay] in
            try? await Task.sleep(for: pickDelay)
            guard let self, !Task.isCancelled else { return }
            self.pickTask = nil
            guard self.isOn, self.savedRadio == nil,
                  let best = self.radios.filter({ !self.passedOver.contains($0.id) }).max(by: { $0.rssi < $1.rssi }) else { return }
            self.connect(to: best, picked: true)
        }
    }

    /// An automatically picked radio that never finished connecting: drop it and try the next one.
    private func passOver(_ id: UUID) {
        passedOver.insert(id)
        autoPicked = nil
        pickWatch = nil
        defaults.removeObject(forKey: Self.radioKey)
        defaults.removeObject(forKey: Self.unconfirmedKey)
        link?.disconnect()
        radioName = nil
        licensed = false
        myNode = nil
        resetSettings()
        link?.scan()
        pickIfNeeded()
    }

    func forget() {
        letGoByHand = false
        letGoForBackground = false
        if status == .released { status = .searching }
        // Forgotten on purpose: not picked again on its own until DLChat restarts, but still listed to choose.
        if let saved = savedRadio { passedOver.insert(saved) }
        pickWatch?.cancel(); pickWatch = nil
        autoPicked = nil
        defaults.removeObject(forKey: Self.radioKey)
        defaults.removeObject(forKey: Self.unconfirmedKey)
        link?.disconnect()
        radioName = nil
        licensed = false
        myNode = nil
        resetSettings()
        nodes = [:]
        // Kept chats stay when the radio is forgotten: the person chose to keep them, and only Wipe or a
        // shorter setting erases them. Memory-only chats go, as before.
        if archive.keep == .off { clearTexts() } else { unread = [:]; open = nil; seenTexts = [] }
        radios = []
        link?.scan()
    }

    // MARK: Send

    /// Hands a sealed Nearby wire message to the radio. False (with `problem` set) if it cannot go.
    @discardableResult
    func send(_ wire: Data) -> Bool {
        guard isOn, status == .ready else { return false }
        guard !licensed else { problem = "The radio is in licensed (ham) mode, where encrypted messages are not allowed. Nothing was sent by radio."; return false }
        guard !regionUnset else { problem = "Set the radio's region in Settings first. Nothing was sent by radio."; return false }
        guard wire.count <= Meshtastic.maxPayload else { problem = "Too long for the radio. Shorten the message to send it by radio."; return false }
        guard let packet = try? Meshtastic.broadcastPacket(payload: wire, id: Self.packetID(),
                                                           hops: Meshtastic.hopLimit(currentLoRa: loraRaw)) else { return false }
        seen.insert(wire)
        problem = nil
        link?.write(packet)
        return true
    }

    // MARK: Link

    private func start() {
        guard link == nil else { return }
        let link = makeLink()
        self.link = link
        isRunning = true
        link.onFound = { [weak self] radio in
            guard let self else { return }
            if let i = self.radios.firstIndex(where: { $0.id == radio.id }) { self.radios[i] = radio } else { self.radios.append(radio) }
            self.pickIfNeeded()
        }
        link.onState = { [weak self] in self?.linkState($0) }
        link.onFrame = { [weak self] in self?.frame($0) }
        if let saved = savedRadio { link.connect(saved) } else { link.scan() }
    }

    private func stop() {
        letGoByHand = false
        letGoForBackground = false
        pickTask?.cancel(); pickTask = nil
        pickWatch?.cancel(); pickWatch = nil
        autoPicked = nil
        link?.disconnect()
        link = nil
        isRunning = false
        status = .off
        radios = []
        problem = nil
    }

    private func linkState(_ state: RadioLinkState) {
        // Let go on purpose: late reports from the old link do not change that.
        guard status != .released else { return }
        switch state {
        case .bluetoothOff: status = .bluetoothOff
        case .unauthorized: status = .unauthorized
        case .idle, .scanning: status = savedRadio == nil ? .searching : .connecting
        case .connecting: status = .connecting
        case .busy: status = .busy
        case .disconnected: status = .disconnected
        case .ready:
            askForConfig()
        }
    }

    /// Ask for the radio's state; it answers with who it is and its settings, then config_complete_id.
    private func askForConfig() {
        configID = Self.packetID()
        link?.write(Meshtastic.wantConfig(id: configID))
    }

    private static func packetID() -> UInt32 { UInt32.random(in: 1...UInt32.max) }

    private func resetSettings() {
        regionUnset = false
        loraRaw = nil
        positionRaw = nil
        positionShares = false
        primaryChannel = nil
        channels = []
        presetName = nil
        locationTried = false
        locationNote = nil
        applying = false
    }

    /// GPS off, no fixed position, and no position on the primary channel, in one saved batch.
    private func turnOffLocationIfNeeded() {
        let channelShares = (primaryChannel?.precision ?? 0) != 0
        guard positionShares || channelShares else {
            if locationTried { locationNote = "Location sharing turned off on this radio." }
            return
        }
        guard !locationTried else {
            locationNote = "DLChat could not turn off location sharing on this radio. Turn it off in the Meshtastic app before using it."
            return
        }
        guard let node = myNode else { return }
        locationTried = true
        applying = true
        locationNote = "Turning off location sharing on this radio…"
        var changes: [Data] = []
        if positionShares, let raw = positionRaw { changes.append(Meshtastic.locationOff(currentPosition: raw)) }
        if channelShares, let raw = primaryChannel?.raw, let admin = Meshtastic.channelWithoutPosition(currentChannel: raw) { changes.append(admin) }
        for admin in [Meshtastic.beginEdit] + changes + [Meshtastic.commitEdit] {
            link?.write(Meshtastic.adminPacket(admin, to: node, id: Self.packetID()))
        }
        askForConfig()  // read the settings back to confirm; a restart asks again on reconnect
    }

    private func frame(_ data: Data) {
        let parsed = Meshtastic.parse(data)
        if status == .ready { noteListening() }
        if case .nodeInfo(let num, _, _, _) = parsed, num != myNode, let node = Meshtastic.meshNode(fromNodeInfo: data) {
            remember(node)
        }
        switch parsed {
        case .myInfo(let num):
            myNode = num
        case .nodeInfo(let num, let longName, _, let isLicensed) where num == myNode:
            if !longName.isEmpty { radioName = longName }
            licensed = isLicensed
        case .loraConfig(let raw, let region):
            loraRaw = raw
            regionUnset = region == 0
            presetName = Meshtastic.presetName(currentLoRa: raw)
        case .positionConfig(let raw, let shares):
            positionRaw = raw
            positionShares = shares
        case .channel(let raw, let index, let precision):
            if index == 0 { primaryChannel = (raw, precision) }
            noteChannel(raw, index: UInt32(truncatingIfNeeded: index))
        case .configComplete(let id) where id == configID && status != .released:
            status = .ready
            // Connected and talking: this radio is kept and reconnected to from now on.
            pickWatch?.cancel(); pickWatch = nil
            autoPicked = nil
            applying = false
            // Not confirmed as theirs: change nothing on a radio that may belong to someone else.
            if isMine { turnOffLocationIfNeeded() }
        case .rebooted:
            guard status != .released else { break }
            status = .connecting
            if let saved = savedRadio { link?.connect(saved) }
        case .packet(_, Meshtastic.privateAppPort, let payload):
            receive(payload)
        case .packet(_, Meshtastic.textPort, _):
            if let packet = Meshtastic.packet(fromRadio: data) { receiveText(packet) }
        case .packet(_, Meshtastic.routingPort, _):
            if let packet = Meshtastic.packet(fromRadio: data) { receiveRouting(packet) }
        case .packet(let from, Meshtastic.positionPort, let payload) where from != myNode && from != 0:
            // A radio broadcast where it is: update or add it.
            let (lat, lon) = Meshtastic.coordinates(Meshtastic.Reader.fields(payload) ?? [])
            var node = nodes[from] ?? MeshNode(num: from, source: .radio)
            if lat != nil { node.latitude = lat; node.longitude = lon }
            node.lastHeard = Date()
            remember(node)
        case .packet(let from, Meshtastic.nodeInfoPort, let payload) where from != myNode && from != 0:
            let user = Meshtastic.Reader.fields(payload) ?? []
            var node = nodes[from] ?? MeshNode(num: from, source: .radio)
            node = MeshNode(num: from, longName: user.string(2) ?? node.longName, shortName: user.string(3) ?? node.shortName,
                            latitude: node.latitude, longitude: node.longitude, lastHeard: Date(), hops: node.hops,
                            publicKey: user.lastBytes(8) ?? node.publicKey, source: .radio)
            remember(node)
        default:
            break
        }
    }

    private func remember(_ node: MeshNode) {
        guard nodes[node.num] != nil || nodes.count < Self.maxNodes else { return }
        nodes[node.num] = node
    }

    private func receive(_ wire: Data) {
        // A busy or hostile mesh must not grow this without end. After a reset a late repeat is
        // handed on once more; the message store drops it by its identity.
        if seen.count >= Self.maxSeen { seen.removeAll() }
        guard seen.insert(wire).inserted else { return }  // our own echo, or a repeat from another hop
        onWire?(wire)
    }

    /// Panic wipe and duress: disconnect and forget the radio and the setting.
    func wipe() {
        stop()
        passedOver = []
        defaults.removeObject(forKey: Self.radioKey)
        defaults.removeObject(forKey: Self.unconfirmedKey)
        defaults.set(false, forKey: Self.onKey)  // a wipe leaves the radio off, like online chat
        defaults.removeObject(forKey: Self.lawAcceptedKey)  // and asks for the radio rules again
        isOn = false
        radioName = nil
        licensed = false
        myNode = nil
        resetSettings()
        nodes = [:]
        // Before the Vault is erased: no save may be pending, and the setting is back to memory only.
        saveTask?.cancel(); saveTask = nil
        archive = MeshArchive()
        clearTexts()
        seen = []
    }
}

// MARK: Meshtastic chats

extension MeshtasticModel {
    /// The radios this phone can direct-message: heard by its own radio, ones with a conversation first, then most recently heard.
    var directNodes: [MeshNode] {
        nodes.values.filter { $0.source == .radio }.sorted { a, b in
            let ca = texts[.direct(a.num)]?.last?.at, cb = texts[.direct(b.num)]?.last?.at
            if (ca != nil) != (cb != nil) { return ca != nil }
            if let ca, let cb, ca != cb { return ca > cb }
            return (a.lastHeard ?? .distantPast) > (b.lastHeard ?? .distantPast)
        }
    }

    func title(of conversation: MeshConversation) -> String {
        switch conversation {
        case .channel(let index):
            return channels.first { $0.index == index }?.title(preset: presetName) ?? "Channel \(index)"
        case .direct(let num):
            return nodes[num]?.displayName ?? MeshNode(num: num, source: .radio).displayName
        }
    }

    func channel(_ index: UInt32) -> Meshtastic.ChannelInfo? { channels.first { $0.index == index } }

    var unreadDirect: Int { unread.filter { $0.key.isDirect }.values.reduce(0, +) }

    /// Shows a conversation in Chat and marks it read.
    func openConversation(_ conversation: MeshConversation?) {
        open = conversation
        if let conversation { unread[conversation] = nil }
    }

    func setViewing(_ on: Bool) {
        viewing = on
        if on, let open { unread[open] = nil }
    }

    /// Sends a plain Meshtastic text. Returns a problem to show, or nil once the radio has it.
    func sendText(_ text: String, in conversation: MeshConversation) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        guard isOn else { return "The radio is off. Turn it on in Settings > Meshtastic radio." }
        guard status == .ready, let me = myNode else { return "The radio is not connected yet. Nothing was sent." }
        guard !regionUnset else { return "Set the radio's region in Settings first. Nothing was sent." }
        let bytes = body.utf8.count
        guard bytes <= Meshtastic.maxTextBytes else {
            return "Too long for Meshtastic: \(bytes) of \(Meshtastic.maxTextBytes) bytes. Shorten it to send."
        }
        let id = Self.packetID()
        let packet: Data?
        switch conversation {
        case .channel(let index):
            guard channel(index) != nil else { return "The radio no longer has this channel." }
            packet = try? Meshtastic.textPacket(body, to: Meshtastic.broadcast, channel: index, id: id, hops: Meshtastic.hopLimit(currentLoRa: loraRaw))
        case .direct(let num):
            guard !licensed else { return "The radio is in licensed (ham) mode, where private messages are not allowed. Nothing was sent." }
            guard num != me else { return "That is your own radio." }
            packet = try? Meshtastic.textPacket(body, to: num, id: id, hops: Meshtastic.hopLimit(currentLoRa: loraRaw),
                                                publicKey: nodes[num]?.publicKey)
        }
        guard let packet else { return "The radio could not take this message." }
        link?.write(packet)
        append(MeshText(packetID: id, from: me, text: body, at: Date(), outgoing: true, isPrivate: conversation.isDirect, hops: nil,
                        state: .sending), to: conversation, unread: false)
        return nil
    }

    func receiveText(_ p: Meshtastic.Packet) {
        guard let me = myNode, p.from != me, p.from != 0 else { return }
        let conversation: MeshConversation
        if p.isBroadcast {
            guard channel(p.channel) != nil else { return }
            conversation = .channel(p.channel)
        } else if p.to == me {
            conversation = .direct(p.from)
        } else {
            return  // addressed to another radio
        }
        guard seenTexts.insert(UInt64(p.from) << 32 | UInt64(p.id)).inserted || p.id == 0 else { return }
        let text = Meshtastic.cleanText(p.payload)
        guard !text.isEmpty else { return }
        if nodes[p.from] == nil { remember(MeshNode(num: p.from, lastHeard: Date(), source: .radio)) } else { nodes[p.from]?.lastHeard = Date() }
        let message = MeshText(packetID: p.id, from: p.from, text: text, at: Date(), outgoing: false,
                               isPrivate: p.pkiEncrypted, hops: p.hops, state: .received)
        append(message, to: conversation, unread: !(viewing && open == conversation))
    }

    /// An acknowledgement or delivery error for something this phone sent.
    func receiveRouting(_ p: Meshtastic.Packet) {
        guard p.requestID != 0 else { return }
        for (conversation, list) in texts {
            guard let i = list.lastIndex(where: { $0.outgoing && $0.packetID == p.requestID }) else { continue }
            let error = Meshtastic.routingError(p.payload)
            let state: MeshText.State
            if error != 0 {
                state = .failed(Meshtastic.routingProblem(error))
            } else if case .direct(let num) = conversation {
                state = p.from == num ? .delivered : (list[i].state == .delivered ? .delivered : .relayed)
            } else {
                state = .relayed
            }
            archive.texts[conversation]?[i].state = state
            changed()
            return
        }
    }

    private func noteChannel(_ raw: Data, index: UInt32) {
        guard index < Self.maxChannels else { return }  // a radio has 8 channels; more is not a real radio
        channels.removeAll { $0.index == index }
        if let info = Meshtastic.channelInfo(raw) { channels.append(info) }
        channels.sort { $0.index < $1.index }
    }

    private func append(_ message: MeshText, to conversation: MeshConversation, unread isUnread: Bool) {
        archive.append(message, to: conversation)
        if !message.outgoing, case .channel(let index) = conversation { archive.counted(channel: index, at: message.at) }
        if isUnread { unread[conversation, default: 0] += 1 }
        changed()
    }

    private func clearTexts() {
        archive.texts = [:]
        archive.hours = []
        unread = [:]
        open = nil
        seenTexts = []
    }
}

// MARK: Keeping Meshtastic chats

/// Where kept Meshtastic chats are saved: a sealed file in the Vault (`MeshArchiveFile`), or a fake in tests.
@MainActor
protocol MeshArchiveStore: AnyObject {
    func load() throws -> MeshArchive?
    func save(_ archive: MeshArchive) throws
    func delete()
}

extension MeshtasticModel {
    /// Reads what was kept, once. Called at launch and again on returning to the app if the read failed
    /// (the store cannot be read while the iPhone is locked).
    func useArchive(_ store: MeshArchiveStore) {
        archiveStore = store
        loadArchive()
    }

    func loadArchive() {
        guard !archiveLoaded, let archiveStore else { return }
        let saved: MeshArchive?
        do { saved = try archiveStore.load() } catch { return }  // try again later, and save nothing until then
        archiveLoaded = true
        guard var merged = saved else { return }  // no file: nothing was kept
        merged.restored()
        // Anything heard since launch, before the read, comes after what was kept.
        for (conversation, list) in archive.texts { for m in list { merged.append(m, to: conversation) } }
        for hour in archive.hours {
            if let i = merged.hours.firstIndex(where: { $0.start == hour.start }) {
                merged.hours[i].counts.merge(hour.counts, uniquingKeysWith: +)
            } else {
                merged.hours.append(hour)
            }
        }
        merged.hours.sort { $0.start < $1.start }
        merged.purge(now: Date())
        archive = merged
        for list in archive.texts.values { for m in list where !m.outgoing { seenTexts.insert(UInt64(m.from) << 32 | UInt64(m.packetID)) } }
    }

    /// Picks how long Meshtastic chats are kept. `.off` deletes the saved file at once; a shorter period
    /// drops what is older straight away.
    func setKeep(_ value: Retention) {
        loadArchive()
        archive.keep = value
        archive.purge(now: Date())
        if value == .off {
            saveTask?.cancel(); saveTask = nil
            archiveStore?.delete()
        } else {
            saveNow()
        }
    }

    /// Drops what has outlived the setting. Called on returning to the app.
    func purgeExpired() {
        loadArchive()
        let before = archive
        archive.purge(now: Date())
        if archive != before { changed() }
    }

    /// Saves at once (going to the background), instead of waiting for the next scheduled save.
    func saveNow() {
        saveTask?.cancel(); saveTask = nil
        guard archive.keep != .off, archiveLoaded, let archiveStore else { return }
        try? archiveStore.save(archive)
    }

    /// Marks this hour as listened to. Checked before changing anything: frames arrive many times a minute.
    private func noteListening() {
        let now = Date()
        guard archive.hours.last?.start != MeshHour.start(of: now) else { return }
        archive.listened(at: now)
        changed()
    }

    /// Something kept changed: save a few seconds later, so a busy channel does not rewrite the file per message.
    private func changed() {
        guard archive.keep != .off, archiveLoaded, archiveStore != nil, saveTask == nil else { return }
        saveTask = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
