import DLCore
import Foundation
import Observation
import TorKit
import UIKit

/// Online chat over Nostr relays: asks once, then stays on until turned off in Settings. Sends the
/// same sealed frame Nearby sends; receives into the same message store; queues while offline.
@MainActor
@Observable
final class OnlineModel {
    /// Chosen 2026-11-07 (owner asked for Tor-friendly relays); each passed a real sealed round trip
    /// both through Tor and directly. Dropped: nos.lol (unreachable from Tor exits), Damus and
    /// relay.nostr.net (require NIP-42 sign-in to read gift wraps, then refuse every sign-in:
    /// "relay needs serviceUrl to be configured before AUTH can work"). Changeable in Settings.
    static let defaultRelays = ["wss://relay.primal.net", "wss://relay.nostrhub.fr", "wss://nostr.data.haus"]
    /// Relays that now refuse every DLChat post, dropped from saved lists too. nostr.bitcoiner.social
    /// (2026-11-12): "pubkey is not in our web of trust"; DLChat signs each post with a throwaway key.
    static let refusingRelays: Set<String> = ["wss://nostr.bitcoiner.social"]

    /// nil until the person has been asked.
    private(set) var enabled: Bool?
    private(set) var relays: [String]
    private(set) var connected = 0
    /// iCloud mailbox with push, off until the person turns it on in Settings.
    private(set) var cloudOn: Bool
    /// Read-once messages: shown in the chat while the app runs, never stored.
    private(set) var transient: [StoredMessage] = []
    /// Retention "Don't keep": messages this phone sent, shown for this session only.
    private(set) var unkept: [StoredMessage] = []
    /// Relay traffic through Tor (owner decision 2026-11-07): on by default, can be turned off in Settings.
    private(set) var torOn: Bool
    /// Tor's bootstrap percentage while it connects; its proxy port once ready.
    private(set) var torProgress = 0
    private(set) var torPort: UInt16?
    private(set) var torFailed = false

    @ObservationIgnored private let groups: GroupModel
    @ObservationIgnored private let defaults: UserDefaults
    /// One pool per group id: separate sockets (and Tor circuits), so relays cannot tell that two groups
    /// share a member, and each relay is only ever signed in to one group's mailboxes.
    @ObservationIgnored private var pools: [UUID: RelayPool] = [:]
    @ObservationIgnored private let cloud: CloudCarrier
    @ObservationIgnored private var active = false
    /// Counts messages newly stored from any carrier, so RootView can show the in-app banner.
    private(set) var arrivals = 0
    /// Leaving the screen keeps relays open this long (iOS allows about 30 seconds), so a quick reply still notifies.
    static let backgroundGrace: Duration = .seconds(25)
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var seen: Set<String> = []
    /// Groups whose relays have handed over everything stored since the last `refresh()`.
    @ObservationIgnored private var caughtUp: Set<UUID> = []
    /// Sealed messages that could not be opened or saved because the iPhone was locked (its keys and store
    /// cannot be read then). Memory only; tried again when the app is next in front.
    @ObservationIgnored private var heldWires: [Data] = []
    static let maxHeldWires = 200
    /// False while the iPhone is locked. Tests replace it.
    @ObservationIgnored var canReadKeys: () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    @ObservationIgnored private var torStarting = false
    /// Bumped whenever Tor is turned off or wiped, so a start that finishes late is ignored.
    @ObservationIgnored private var torRun = 0
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private let torStart: TorStart

    typealias TorStart = @MainActor (_ progress: @escaping @Sendable (Int) -> Void) async throws -> UInt16
    static let torDirectory = URL.applicationSupportDirectory.appending(path: "tor", directoryHint: .isDirectory)

    static let enabledKey = "online.enabled", relaysKey = "online.relays", syncKey = "online.lastSync", cloudKey = "online.cloud", torKey = "online.tor"

    init(groups: GroupModel, defaults: UserDefaults = .standard, torStart: TorStart? = nil) {
        self.groups = groups
        self.defaults = defaults
        self.torStart = torStart ?? { progress in
            var dir = OnlineModel.torDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Tor's guard state stays on this phone: not in iCloud or computer backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            return try await Tor.shared.start(dataDirectory: dir, progress: progress)
        }
        torOn = defaults.object(forKey: Self.torKey) == nil ? true : defaults.bool(forKey: Self.torKey)
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool
        let saved = defaults.stringArray(forKey: Self.relaysKey)?.filter { !Self.refusingRelays.contains($0) }
        relays = saved.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultRelays
        defaults.removeObject(forKey: Self.syncKey)  // older builds kept the last sync time in plain settings
        cloudOn = CloudCarrier.isConfigured && defaults.bool(forKey: Self.cloudKey)
        cloud = CloudCarrier(defaults: defaults)
        cloud.onEvent = { [weak self] in self?.receive($0) }
        HygieneAppDelegate.onPush = { [weak self] in await self?.fetchCloud() ?? false }
    }

    /// The relays connected for a group right now, for Chat's ^ menu.
    func openRelays(for groupID: UUID) -> [String] { pools[groupID]?.openRelays ?? [] }

    private func pool(for groupID: UUID) -> RelayPool {
        if let existing = pools[groupID] { return existing }
        let pool = RelayPool()
        pool.onEvent = { [weak self] in self?.receive($0) }
        // Signs in with this group's mailboxes only.
        pool.authEvents = { [weak self] challenge, url in
            guard let self, let group = self.groups.groups.first(where: { $0.id == groupID }),
                  let keys = try? self.groups.keys(for: group) else { return [] }
            return (try? Online.authEvents(challenge: challenge, relay: url, keys: [keys])) ?? []
        }
        pool.onCaughtUp = { [weak self] in self?.noteCaughtUp(groupID) }
        pool.onConnected = { [weak self] _ in
            guard let self else { return }
            let count = self.pools.values.map(\.connectedCount).max() ?? 0
            self.connected = count
            if count > 0 { Task { await self.flushQueue() } }
        }
        pools[groupID] = pool
        return pool
    }

    private func disconnectAll() {
        pools.values.forEach { $0.disconnect() }
        pools = [:]
        caughtUp = []
        connected = 0
    }

    /// When this phone last had everything its relays hold. Kept in the Keychain (this device only, never in
    /// a backup), not in plain settings: it tells when the app was last used.
    private var lastSync: Date? {
        guard let data = try? groups.vault.secret(account: Self.syncKey),
              let seconds = String(data: data, encoding: .utf8).flatMap({ TimeInterval($0) }) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A relay of this group has sent everything it stored. Only once every group has heard that does the
    /// next launch start from now: moving it on at the first message would skip older ones that a slower
    /// relay had not handed over yet.
    private func noteCaughtUp(_ groupID: UUID) {
        caughtUp.insert(groupID)
        guard !pools.isEmpty, caughtUp.isSuperset(of: pools.keys) else { return }
        try? groups.vault.setSecret(Data(String(Date().timeIntervalSince1970).utf8), account: Self.syncKey)
    }

    var isOn: Bool { enabled == true }

    // MARK: Settings

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        refresh()
    }

    /// wss, or plain ws only to this phone, a home network or an onion address (Tor encrypts that
    /// itself), so a public relay typed as ws:// cannot carry the mailbox keys in the clear.
    static func isAllowedRelay(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        switch url.scheme?.lowercased() {
        case "wss": return true
        case "ws":
            if ["localhost", "::1"].contains(host) || host.hasSuffix(".onion") || host.hasSuffix(".local") { return true }
            let o = host.split(separator: ".").compactMap { Int($0) }
            guard o.count == 4 else { return false }
            return o[0] == 127 || o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && (16...31).contains(o[1]))
        default: return false
        }
    }

    func setRelays(_ list: [String]) {
        let clean = list.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { URL(string: $0).map(Self.isAllowedRelay) ?? false }
        relays = Array(NSOrderedSet(array: clean)) as? [String] ?? clean
        defaults.set(relays, forKey: Self.relaysKey)
        refresh()
    }

    /// Tor on: relays see a Tor exit's address instead of this phone's. Off: Tor stops all traffic.
    func setTor(_ on: Bool) {
        torOn = on
        defaults.set(on, forKey: Self.torKey)
        torFailed = false
        if !on {
            torRun += 1
            torPort = nil
            torProgress = 0
            Task { await Tor.shared.pause() }
        }
        refresh()
    }

    private func startTor() {
        guard !torStarting else { return }
        torStarting = true
        torFailed = false
        torProgress = 0
        let myRun = torRun
        Task { [weak self] in
            guard let self else { return }
            do {
                let port = try await torStart { [weak self] p in Task { @MainActor in self?.torProgress = p } }
                torStarting = false
                // Turned off or wiped while connecting: this start is stale.
                guard torOn, myRun == torRun else { return }
                torPort = port
            } catch {
                torStarting = false
                guard myRun == torRun else { return }
                torFailed = true
            }
            refresh()
        }
    }

    /// Internet Messages run only over Tor, even with no group or group online chat off: starts it if needed.
    func requestTor() {
        guard torOn, torPort == nil, !torFailed else { return }
        startTor()
    }

    /// Tor failed: clear the failure and connect again.
    func retryTor() {
        torFailed = false
        refresh()
    }

    /// Turns the iCloud mailbox on (asking for notification permission first) or off.
    func setCloud(_ on: Bool) async {
        guard CloudCarrier.isConfigured else { return }
        if on, !(await CloudCarrier.askForNotifications()) { return }
        cloudOn = on
        defaults.set(on, forKey: Self.cloudKey)
        if on { UIApplication.shared.registerForRemoteNotifications() } else { await cloud.wipe() }
        refresh()
    }

    private var masterKeys: [Keys] { groups.groups.compactMap { try? groups.keys(for: $0) } }

    private var watchedMailboxes: [String] {
        masterKeys.flatMap { Online.mailboxes(for: $0, now: Date()) }
    }

    /// True when the fetch brought anything in.
    private func fetchCloud() async -> Bool {
        guard isOn, cloudOn else { return false }
        await cloud.start()
        return await cloud.fetch(mailboxes: watchedMailboxes) > 0
    }

    /// Foreground or not: sockets only run while the app is active.
    func setActive(_ value: Bool) {
        graceTask?.cancel()
        graceTask = nil
        guard !value else {
            endBackgroundTask()
            active = true
            storeHeldWires()
            refresh()
            return
        }
        guard active, backgroundTask == .invalid else { return }
        // Leaving the screen: keep listening briefly, then close every socket as before.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "dlchat-relays") { [weak self] in
            MainActor.assumeIsolated { self?.goInactive() }
        }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.backgroundGrace)
            guard !Task.isCancelled else { return }
            self?.goInactive()
        }
    }

    private func goInactive() {
        graceTask?.cancel()
        graceTask = nil
        active = false
        refresh()
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Groups changed: watch their mailboxes.
    func refresh() {
        guard isOn, active, !groups.groups.isEmpty else { disconnectAll(); return }
        if torOn, torPort == nil {
            // Fail closed: never a direct socket while Tor is meant to be on but not ready.
            disconnectAll()
            if !torFailed { startTor() }
            return
        }
        let last = lastSync ?? Date().addingTimeInterval(-Online.lifetime)
        caughtUp = []  // each subscription below makes the relays send their stored events again
        let urls = relays.compactMap(URL.init(string:))
        let keyed = groups.groups.compactMap { group in (try? groups.keys(for: group)).map { (group.id, $0) } }
        for (id, pool) in pools where !keyed.contains(where: { $0.0 == id }) { pool.disconnect(); pools[id] = nil }
        for (id, keys) in keyed {
            let pool = pool(for: id)
            pool.connect(urls, via: torOn ? torPort : nil)
            // Back past the last look by the blur on created_at, so nothing sent while we were away is missed.
            pool.subscribe(Online.filter(mailboxes: Online.mailboxes(for: keys, now: Date()), since: last.addingTimeInterval(-3 * 86_400)))
        }
        let mailboxes = watchedMailboxes
        if cloudOn {
            Task {
                await cloud.start()
                await cloud.subscribe(mailboxes: mailboxes)
                await cloud.fetch(mailboxes: mailboxes)
                await cloud.deleteExpired()
            }
        }
    }

    // MARK: Send

    /// Sends a Nearby wire message for `keySet`'s group online. Returns how many relays took it
    /// (0 means it is queued and goes out when a relay is reachable).
    /// `sentBy`: another carrier already took it (e.g. "radio"), so it is recorded that way rather
    /// than as waiting when no relay does.
    @discardableResult
    /// `useRelays` false: the person chose the radio only (Chat's ^ menu), so nothing goes online.
    func send(wire: Data, keySet: KeySet, sentBy: String? = nil, useRelays: Bool = true, skipping: Set<String> = []) async -> Int {
        guard let message = Receiver.readNearby(wire: wire, trying: [keySet.keys]) else { return 0 }
        let keep = groups.retention != .off
        let transientID = UUID().uuidString
        if message.readOnce {
            transient.append(StoredMessage(id: transientID, groupID: keySet.groupID, room: keySet.room, text: message.text,
                                           sentAt: message.sentAt, recordedAt: Date(), repairedWord: nil, duress: message.duress,
                                           timesHeard: 1, outgoing: true, via: "online", replyTo: message.replyTo?.fingerprint))
        } else if keep {
            groups.recordSent(message, from: keySet, via: isOn && useRelays ? "online" : (sentBy ?? "queued"), relays: nil)
        }
        guard isOn, useRelays, let event = try? Online.event(wire: wire, keys: keySet.keys) else {
            if !keep, !message.readOnce { showUnkept(message, keySet, via: sentBy, relays: nil) }
            if message.readOnce { settleTransient(transientID, via: sentBy, relays: nil) }
            return 0
        }
        seen.insert(event.id)
        var accepted = await pool(for: keySet.groupID).publish(event, skipping: skipping)
        if cloudOn, let mailbox = event.tags.first?.last, await cloud.send(event, mailbox: mailbox) { accepted += 1 }
        if message.readOnce {
            settleTransient(transientID, via: route(sentBy: sentBy, relays: accepted), relays: accepted > 0 ? accepted : nil)
        } else {
            if keep {
                groups.recordSent(message, from: keySet, via: route(sentBy: sentBy, relays: accepted) ?? "queued", relays: accepted)
            } else {
                showUnkept(message, keySet, via: route(sentBy: sentBy, relays: accepted), relays: accepted > 0 ? accepted : nil)
            }
        }
        return accepted
    }

    /// Every route that took a message, joined by "+": "radio", and "online-tor" or "online-direct" for
    /// relays (whether Tor carried it). Chat shows each one. ("online" alone is an older or in-flight record.)
    private func route(sentBy: String?, relays: Int) -> String? {
        let parts = [sentBy, relays > 0 ? (torOn ? "online-tor" : "online-direct") : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "+")
    }

    /// A read-once message is never stored, so it cannot wait in the queue: once sending is over its bubble
    /// says how it left, or "unsent" when nothing took it, instead of "sending" for ever.
    private func settleTransient(_ id: String, via: String?, relays: Int?) {
        guard let i = transient.firstIndex(where: { $0.id == id }) else { return }
        transient[i].via = via ?? "unsent"
        transient[i].relays = relays
    }

    /// Retention off: a sent message is shown for this session only. One that nothing took is stored
    /// as queued all the same, so it still goes out when a relay is reachable.
    private func showUnkept(_ message: ReadMessage, _ keySet: KeySet, via: String?, relays: Int?) {
        guard let via else { groups.recordSent(message, from: keySet, via: "queued", relays: nil); return }
        unkept.append(StoredMessage(id: UUID().uuidString, groupID: keySet.groupID, room: keySet.room, text: message.text,
                                    sentAt: message.sentAt, recordedAt: Date(), repairedWord: nil, duress: message.duress,
                                    timesHeard: 1, outgoing: true, via: via, relays: relays, replyTo: message.replyTo?.fingerprint))
    }

    /// Re-sends messages that were waiting for a connection, newly sealed. One flush at a time: each
    /// relay that connects asks for one, and overlapping flushes would send each message again.
    func flushQueue() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        let keySets = groups.keySets()
        for group in groups.groups {
            for stored in groups.chatMessages(groupID: group.id) where stored.isOutgoing && stored.via == "queued" {
                guard let keySet = keySets.first(where: { $0.groupID == group.id && $0.room == stored.room }),
                      let frame = try? Composer.composeNearby(text: stored.text, keys: keySet.keys, sentAt: stored.sentAt, flags: stored.duress ? 1 : 0,
                                                                replyTo: stored.replyTo.map(ReplyTo.init(fingerprint:)), callSign: groups.callSign),
                      let event = try? Online.event(wire: NearbyWire.wire(frame: frame, ttl: 0), keys: keySet.keys) else { continue }
                seen.insert(event.id)
                let accepted = await pool(for: group.id).publish(event)
                guard accepted > 0, let message = Receiver.readNearby(wire: NearbyWire.wire(frame: frame, ttl: 0), trying: [keySet.keys]) else { continue }
                // A new seal means a new identity: drop the queued copy and keep the sent one.
                groups.deleteMessage(stored)
                if groups.retention == .off {
                    showUnkept(message, keySet, via: route(sentBy: nil, relays: accepted), relays: accepted)
                } else {
                    groups.recordSent(message, from: keySet, via: route(sentBy: nil, relays: accepted) ?? "queued", relays: accepted)
                }
            }
        }
    }

    /// A read receipt to the group's relays. Not stored, not queued: if no relay takes it, it is dropped.
    func sendReceipt(wire: Data, groupID: UUID, keys: Keys) async {
        guard isOn, let event = try? Online.event(wire: wire, keys: keys) else { return }
        seen.insert(event.id)
        _ = await pool(for: groupID).publish(event)
    }

    // MARK: Support

    /// Settings → Send anonymously needs online chat on, with Tor.
    var canSendSupport: Bool { isOn && torOn }

    /// Settings → Send anonymously: the report sealed to the developer (DLCore `SupportReport`), through
    /// Tor only, on a pool of its own (its own sockets and Tor circuit), so no relay can tie it to a
    /// group. Returns how many relays took it. Throws `OnlineError.tooLarge` for a report over 4 KB.
    func sendSupport(_ text: String) async throws -> Int {
        guard canSendSupport else { return 0 }
        let event = try SupportReport.event(text: text)
        // Tor may still be starting, or not started at all when there are no groups yet.
        if torPort == nil, !torStarting { startTor() }
        let deadline = ContinuousClock.now + .seconds(90)
        while torPort == nil, torOn, !torFailed, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(500)) }
        guard torOn, let torPort else { return 0 }
        let pool = RelayPool()
        pool.connect(relays.compactMap(URL.init(string:)), via: torPort)
        let accepted = await pool.publish(event, timeout: .seconds(30))
        pool.disconnect()
        return accepted
    }

    // MARK: Receive

    private func receive(_ event: Online.Event) {
        guard !seen.contains(event.id) else { return }
        // Marked seen only once it opens, so a forged event reusing a real id cannot block the real one.
        guard let opened = Online.wire(from: event, trying: masterKeys), store(wire: opened.wire, id: event.id) else { return }
        seen.insert(event.id)
    }

    /// A sealed message the radio heard. The radio can stay connected while the iPhone is locked, when
    /// neither the keys nor the store can be read: the message waits in memory until the app is in front.
    func storeFromRadio(_ wire: Data) {
        let locked = !canReadKeys() || (groups.keySets().isEmpty && !groups.groups.isEmpty)
        if locked { hold(wire) } else { store(wire: wire) }
    }

    private func hold(_ wire: Data) {
        if heldWires.count < Self.maxHeldWires, !heldWires.contains(wire) { heldWires.append(wire) }
    }

    private func storeHeldWires() {
        guard !heldWires.isEmpty, canReadKeys() else { return }
        let wires = heldWires
        heldWires = []
        wires.forEach { store(wire: $0) }
    }

    /// A sealed Nearby wire message from any carrier (relays, a Meshtastic radio): stored, or kept
    /// in memory only if it is read once. False if no group here opens it.
    @discardableResult
    func store(wire: Data, id: String = UUID().uuidString) -> Bool {
        // A read receipt: noted on our sent messages (if receipts are on here), never shown as a message.
        let receiptKeys = groups.receiptKeySets()
        if let receipt = ReadReceipt.open(wire: wire, trying: receiptKeys.map { $0.keys }) {
            groups.applyReceipt(receipt, groupID: receiptKeys[receipt.keysIndex].groupID)
            return true
        }
        let keySets = groups.keySets()
        guard let message = Receiver.readNearby(wire: wire, trying: keySets.map(\.keys)) else { return false }
        let keySet = keySets[message.keysIndex]
        // Deleted, purged or already read once here: a relay's copy is not shown again.
        guard !groups.isForgotten(message, from: keySet) else { return true }
        if message.readOnce {
            groups.forget(message, from: keySet)
            transient.append(StoredMessage(id: id, groupID: keySet.groupID, room: keySet.room, text: message.text,
                                           sentAt: message.sentAt, recordedAt: Date(), repairedWord: nil, duress: message.duress, timesHeard: 1,
                                           callSign: message.callSign, replyTo: message.replyTo?.fingerprint))
            arrivals += 1
            Notifier.newMessage()
        } else {
            // Not saved (the store is locked): keep the sealed bytes and try again, and announce nothing yet.
            guard let result = groups.recordChat(message, from: keySet) else { hold(wire); return true }
            if result == .new {
                arrivals += 1
                Notifier.newMessage()
            }
        }
        return true
    }

    /// Chat > long press > Delete on a message held only in memory (read once, or "Don't keep").
    func dismiss(id: String) {
        transient.removeAll { $0.id == id }
        unkept.removeAll { $0.id == id }
    }

    /// Panic wipe and duress: drop every socket, forget the settings and anything in memory.
    func wipe() {
        graceTask?.cancel()
        graceTask = nil
        endBackgroundTask()
        disconnectAll()
        let cloud = cloud
        if CloudCarrier.isConfigured { Task { await cloud.wipe() } }
        cloudOn = false
        torOn = true  // back to the default; online itself is off again until asked
        torRun += 1
        torPort = nil
        torProgress = 0
        torFailed = false
        // Tor's cache holds which entry relay this phone uses; pause it and erase it (best effort).
        Task {
            await Tor.shared.pause()
            try? FileManager.default.removeItem(at: Self.torDirectory)
        }
        [Self.enabledKey, Self.relaysKey, Self.syncKey, Self.cloudKey, Self.torKey].forEach(defaults.removeObject(forKey:))
        enabled = nil
        relays = Self.defaultRelays
        try? groups.vault.removeSecret(account: Self.syncKey)
        transient = []
        unkept = []
        seen = []
        heldWires = []
        caughtUp = []
        connected = 0
    }
}
