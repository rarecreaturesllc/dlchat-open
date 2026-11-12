import DLCore
import XCTest
@testable import DLChat

/// A pretend radio: answers the config request like Meshtastic firmware, and passes what one phone
/// sends to every other phone on the same "air" as a received packet.
@MainActor
final class FakeRadio: RadioLink {
    var onFound: ((RadioLinkRadio) -> Void)?
    var onState: ((RadioLinkState) -> Void)?
    var onFrame: ((Data) -> Void)?
    let node: UInt32
    var licensed = false
    /// nil: sends no LoRa settings (older tests). 0: a new radio with no region.
    var region: UInt64?
    var gpsOn = false
    var precision: UInt64 = 0
    /// A radio that takes admin packets but changes nothing.
    var ignoresAdmin = false
    private(set) var adminCount = 0
    var air: [FakeRadio] = []
    private(set) var written: [Data] = []
    private(set) var scanning = false
    let radio = RadioLinkRadio(id: UUID(), name: "Heltec 1234")

    init(node: UInt32) { self.node = node }

    func scan() { scanning = true; onState?(.scanning); onFound?(radio) }
    /// Another app on the phone holds this radio: a plain connect waits, as MeshtasticLink does.
    var heldElsewhere = false
    /// False: a radio that never finishes connecting (someone else's, or its PIN was not entered).
    var answers = true
    private(set) var connected = false
    private(set) var disconnects = 0
    func connect(_ id: UUID, evenIfBusy: Bool) {
        if heldElsewhere && !evenIfBusy { onState?(.busy); return }
        onState?(.connecting)
        guard answers else { return }
        connected = true
        onState?(.ready)
    }
    func disconnect() { scanning = false; connected = false; disconnects += 1 }
    func write(_ data: Data) {
        written.append(data)
        guard let fields = Meshtastic.Reader.fields(data) else { return }
        if let id = fields.varint(3) {  // want_config_id
            var my = Meshtastic.Writer(); my.varint(field: 1, UInt64(node))
            var f = Meshtastic.Writer(); f.bytes(field: 3, my.data); onFrame?(f.data)
            var user = Meshtastic.Writer(); user.bytes(field: 2, Data("Porch radio".utf8)); user.varint(field: 6, licensed ? 1 : 0)
            var info = Meshtastic.Writer(); info.varint(field: 1, UInt64(node)); info.bytes(field: 2, user.data)
            var g = Meshtastic.Writer(); g.bytes(field: 4, info.data); onFrame?(g.data)
            func config(_ field: Int, _ sub: Meshtastic.Writer) {
                var c = Meshtastic.Writer(); c.bytes(field: field, sub.data)
                var f = Meshtastic.Writer(); f.bytes(field: 5, c.data); onFrame?(f.data)
            }
            if let region {
                var lora = Meshtastic.Writer(); lora.varint(field: 1, 1); lora.varint(field: 7, region); lora.varint(field: 9, 1)
                config(6, lora)
            }
            var position = Meshtastic.Writer(); position.varint(field: 1, 900); position.varint(field: 13, gpsOn ? 1 : 0)
            config(2, position)
            var module = Meshtastic.Writer(); module.varint(field: 1, precision)
            var settings = Meshtastic.Writer(); settings.bytes(field: 2, Data([1])); settings.bytes(field: 7, module.data)
            var channel = Meshtastic.Writer(); channel.varint(field: 1, 0); channel.bytes(field: 2, settings.data); channel.varint(field: 3, 1)
            var ch = Meshtastic.Writer(); ch.bytes(field: 10, channel.data); onFrame?(ch.data)
            var done = Meshtastic.Writer(); done.varint(field: 7, id); onFrame?(done.data)
        } else if let packet = fields.bytes(1), let admin = adminPayload(packet) {
            adminCount += 1
            guard !ignoresAdmin else { return }
            if let config = admin.bytes(34).flatMap(Meshtastic.Reader.fields) {
                if let lora = config.bytes(6).flatMap(Meshtastic.Reader.fields), let r = lora.lastVarint(7) { region = r }
                if let pos = config.bytes(2).flatMap(Meshtastic.Reader.fields) {
                    gpsOn = pos.lastVarint(13) == 1 || (pos.lastVarint(3) ?? 0) != 0
                }
            }
            if let channel = admin.bytes(33).flatMap(Meshtastic.Reader.fields),
               let module = channel.lastBytes(2).flatMap(Meshtastic.Reader.fields)?.lastBytes(7).flatMap(Meshtastic.Reader.fields) {
                precision = module.lastVarint(1) ?? 0
            }
        } else if let packet = fields.bytes(1) {
            var p = Meshtastic.Reader.fields(packet) ?? []
            p.insert(Meshtastic.Field(number: 1, value: .fixed32(node)), at: 0)  // the firmware fills in "from"
            var rebuilt = Meshtastic.Writer()
            for f in p {
                switch f.value {
                case .fixed32(let v): rebuilt.fixed32(field: f.number, v)
                case .varint(let v): rebuilt.varint(field: f.number, v)
                case .bytes(let v): rebuilt.bytes(field: f.number, v)
                case .fixed64: break
                }
            }
            var out = Meshtastic.Writer(); out.bytes(field: 2, rebuilt.data)
            for other in air where other !== self { other.onFrame?(out.data) }
        }
    }
}

extension FakeRadio {
    /// The AdminMessage in a packet addressed to this radio, if it is one.
    func adminPayload(_ packet: Data) -> [Meshtastic.Field]? {
        guard let p = Meshtastic.Reader.fields(packet), p.fixed32(2) == node,
              let data = p.bytes(4).flatMap(Meshtastic.Reader.fields), data.varint(1) == 6 else { return nil }
        return data.bytes(2).flatMap(Meshtastic.Reader.fields)
    }
}

@MainActor
final class MeshtasticModelTests: XCTestCase {
    private var cleanup: [() -> Void] = []
    override func tearDown() { cleanup.forEach { $0() }; cleanup = [] }

    /// `accepted`: the person has already accepted the radio rules, as anyone who turned the radio on has.
    private func defaults(accepted: Bool = true) -> UserDefaults {
        let suite = "dlchat.mesh.tests.\(UUID().uuidString)"
        cleanup.append { UserDefaults().removePersistentDomain(forName: suite) }
        let d = UserDefaults(suiteName: suite)!
        if accepted { d.set(true, forKey: MeshtasticModel.lawAcceptedKey) }
        return d
    }

    private struct Phone { let groups: GroupModel; let online: OnlineModel; let mesh: MeshtasticModel; let radio: FakeRadio; let defaults: UserDefaults }

    private func phone(_ phrase: Phrase, node: UInt32, licensed: Bool = false, country: String? = "US",
                       setUp: (FakeRadio) -> Void = { _ in }) throws -> Phone {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-mesh-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Porch", prepared: PreparedGroup(phrase: phrase))
        let groups = GroupModel(vault: vault)
        let d = defaults()
        d.set(false, forKey: OnlineModel.torKey)
        let online = OnlineModel(groups: groups, defaults: d)
        let radio = FakeRadio(node: node)
        radio.licensed = licensed
        setUp(radio)
        let mesh = MeshtasticModel(defaults: d, country: { country }) { radio }
        mesh.onWire = { online.store(wire: $0) }
        return Phone(groups: groups, online: online, mesh: mesh, radio: radio, defaults: d)
    }

    private func wire(_ text: String, _ p: Phone) throws -> Data {
        let keys = p.groups.keySets().first { $0.room == "" }!.keys
        return NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys), ttl: 0)
    }

    /// Off by default (owner decision 2026-11-12): a fresh install never starts the radio or touches
    /// Bluetooth, even once a group exists.
    func testOffByDefaultAndTouchesNoBluetooth() {
        var made = false
        let mesh = MeshtasticModel(defaults: defaults(accepted: false)) { made = true; return FakeRadio(node: 1) }
        XCTAssertFalse(mesh.isOn)
        mesh.startIfWanted()
        XCTAssertFalse(made)
        XCTAssertFalse(mesh.lawAccepted)
    }

    /// The radio can't be turned on until the radio rules are accepted; accepting then turning it on works.
    func testTurningOnNeedsTheRadioRulesAccepted() {
        var made = false
        let mesh = MeshtasticModel(defaults: defaults(accepted: false)) { made = true; return FakeRadio(node: 1) }
        mesh.setOn(true)
        XCTAssertFalse(mesh.isOn)
        XCTAssertFalse(made)
        mesh.acceptLaw()
        mesh.setOn(true)
        XCTAssertTrue(mesh.isOn)
        XCTAssertTrue(made)
    }

    /// Someone who had the radio on in an older build, before the rules had to be accepted, starts with it off.
    func testOnFromAnOlderBuildStaysOffUntilTheRulesAreAccepted() {
        let d = defaults(accepted: false)
        d.set(true, forKey: MeshtasticModel.onKey)
        var made = false
        let mesh = MeshtasticModel(defaults: d) { made = true; return FakeRadio(node: 1) }
        mesh.startIfWanted()
        XCTAssertFalse(mesh.isOn)
        XCTAssertFalse(made)
    }

    /// Turned on (rules accepted) in an earlier launch: it comes back on and reconnects at launch.
    func testOnAndAcceptedStaysOnAcrossLaunches() {
        let d = defaults()
        MeshtasticModel(defaults: d) { FakeRadio(node: 1) }.setOn(true)
        var made = false
        let again = MeshtasticModel(defaults: d) { made = true; return FakeRadio(node: 1) }
        XCTAssertTrue(again.isOn)
        XCTAssertTrue(made)
        XCTAssertTrue(again.isActive)
    }

    /// First run skipped with no group: turning the radio on in Settings starts it, with no group needed
    /// (public channel and direct messages), and turning it off shows off again.
    func testSettingsSwitchStartsTheRadioWithNoGroup() {
        var made = false
        let mesh = MeshtasticModel(defaults: defaults()) { made = true; return FakeRadio(node: 1) }
        XCTAssertFalse(mesh.isActive)
        mesh.setOn(true)
        XCTAssertTrue(made)
        XCTAssertTrue(mesh.isActive)
        mesh.setOn(false)
        XCTAssertFalse(mesh.isActive)
        XCTAssertFalse(mesh.isOn)
    }

    func testTurnedOffStaysOffAcrossLaunches() {
        let d = defaults()
        MeshtasticModel(defaults: d) { FakeRadio(node: 1) }.setOn(false)
        var made = false
        let again = MeshtasticModel(defaults: d) { made = true; return FakeRadio(node: 1) }
        again.startIfWanted()
        XCTAssertFalse(again.isOn)
        XCTAssertFalse(made)
    }

    func testPairsAndBecomesReadyAfterTheHandshake() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1)
        p.mesh.setOn(true)
        XCTAssertTrue(p.radio.scanning)
        XCTAssertEqual(p.mesh.radios.map(\.name), ["Heltec 1234"])
        p.mesh.choose(p.mesh.radios[0])
        XCTAssertEqual(p.mesh.status, .ready)
        XCTAssertEqual(p.mesh.radioName, "Porch radio")
        XCTAssertTrue(p.mesh.isReady)
        XCTAssertNotNil(p.mesh.savedRadio, "remembered for next launch")
    }

    private func paired(_ setUp: (FakeRadio) -> Void = { _ in }) throws -> Phone {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1, setUp: setUp)
        p.mesh.setOn(true)
        p.mesh.choose(p.mesh.radios[0])
        XCTAssertTrue(p.mesh.isReady)
        return p
    }

    /// Owner decision 2026-11-09: by default DLChat lets go when it leaves the screen and takes the radio back on return.
    func testLetsGoInTheBackgroundAndTakesItBack() throws {
        let p = try paired()
        XCTAssertTrue(p.mesh.letsGoInBackground, "on by default")
        p.mesh.setForeground(false)
        XCTAssertEqual(p.mesh.status, .released)
        XCTAssertFalse(p.radio.connected)
        XCTAssertFalse(p.mesh.send(Data([1])), "nothing goes out through a radio DLChat let go of")
        p.mesh.setForeground(true)
        XCTAssertTrue(p.mesh.isReady)
        XCTAssertTrue(p.radio.connected)
    }

    func testCanStayConnectedInTheBackground() throws {
        let p = try paired()
        p.mesh.setLetsGoInBackground(false)
        p.mesh.setForeground(false)
        XCTAssertTrue(p.mesh.isReady)
        XCTAssertTrue(p.radio.connected)
        XCTAssertFalse(MeshtasticModel(defaults: p.defaults) { FakeRadio(node: 1) }.letsGoInBackground, "remembered")
    }

    /// Let go by hand stays let go, even across a trip to the background, until "Use radio here".
    func testLetGoByHandWaitsForUseHere() throws {
        let p = try paired()
        p.mesh.letGo()
        XCTAssertEqual(p.mesh.status, .released)
        XCTAssertTrue(p.mesh.letGoByHand)
        XCTAssertFalse(p.radio.connected)
        p.mesh.setForeground(false)
        p.mesh.setForeground(true)
        XCTAssertEqual(p.mesh.status, .released, "not taken back on its own")
        p.mesh.useHere()
        XCTAssertTrue(p.mesh.isReady)
        XCTAssertFalse(p.mesh.letGoByHand)
    }

    /// Another app on the phone holds the radio: DLChat says so and does not take it unless asked.
    func testBusyRadioIsNotTakenUnlessAsked() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1) { $0.heldElsewhere = true }
        p.mesh.setOn(true)
        p.mesh.choose(p.mesh.radios[0])
        XCTAssertEqual(p.mesh.status, .busy)
        XCTAssertTrue(MeshStatus.text(p.mesh).hasPrefix("Radio busy"))
        XCTAssertFalse(p.radio.connected)
        p.mesh.useHere(evenIfBusy: true)
        XCTAssertTrue(p.mesh.isReady)
    }

    /// No "Pair with" step: the radio found is connected to on its own and kept for next launch.
    func testConnectsToTheRadioItFindsWithNoTap() async throws {
        let radio = FakeRadio(node: 0xA1)
        let mesh = MeshtasticModel(defaults: defaults(), pickDelay: .zero) { radio }
        mesh.setOn(true)
        for _ in 0..<100 where !mesh.isReady { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(mesh.status, .ready)
        XCTAssertEqual(mesh.savedRadio, radio.radio.id)
        XCTAssertEqual(mesh.radioName, "Porch radio")
        XCTAssertNil(mesh.autoPicked, "connected, so no longer on trial")
    }

    /// Picked on its own, the radio may be a stranger's (fixed or no PIN): nothing on it changes until confirmed.
    func testChangesNothingOnAPickedRadioUntilConfirmed() async throws {
        let radio = FakeRadio(node: 0xA1)
        radio.gpsOn = true
        let mesh = MeshtasticModel(defaults: defaults(), pickDelay: .zero) { radio }
        mesh.setOn(true)
        for _ in 0..<100 where !mesh.isReady { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(mesh.isReady)
        XCTAssertFalse(mesh.isMine)
        XCTAssertEqual(radio.adminCount, 0, "no settings sent to a radio that may not be theirs")
        XCTAssertTrue(radio.gpsOn)
        mesh.confirmMine()
        XCTAssertTrue(mesh.isMine)
        XCTAssertFalse(radio.gpsOn, "confirmed: location sharing turned off")
    }

    /// A radio picked on its own that never finishes connecting is dropped, and can still be chosen by hand.
    func testPassesOverARadioThatNeverConnects() async throws {
        let radio = FakeRadio(node: 0xA1)
        radio.answers = false
        let mesh = MeshtasticModel(defaults: defaults(), pickDelay: .zero, pickTimeout: .milliseconds(100)) { radio }
        mesh.setOn(true)
        for _ in 0..<100 where mesh.autoPicked == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(mesh.autoPicked, radio.radio.id)
        for _ in 0..<100 where mesh.savedRadio != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(mesh.savedRadio)
        XCTAssertNil(mesh.autoPicked)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(mesh.savedRadio, "not picked again on its own")
        XCTAssertEqual(mesh.radios.map(\.id), [radio.radio.id], "still listed to choose by hand")
    }

    func testMessageTravelsBetweenTwoPhonesByRadio() throws {
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, node: 0xA1), b = try phone(phrase, node: 0xB2)
        a.radio.air = [a.radio, b.radio]; b.radio.air = a.radio.air
        for p in [a, b] { p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0]) }
        XCTAssertTrue(a.mesh.send(try wire("need water at north gate", a)))
        let got = b.groups.chatMessages(groupID: b.groups.groups[0].id)
        XCTAssertEqual(got.map(\.text), ["need water at north gate"])
        XCTAssertFalse(got[0].isOutgoing)
        XCTAssertEqual(b.online.arrivals, 1, "a new message raises the in-app banner")
        XCTAssertEqual(a.online.arrivals, 0, "our own echo is not news")
    }

    func testAnotherGroupsMessageIsIgnored() throws {
        let a = try phone(try Phrase.generate(words: 10), node: 0xA1), b = try phone(try Phrase.generate(words: 10), node: 0xB2)
        a.radio.air = [a.radio, b.radio]; b.radio.air = a.radio.air
        for p in [a, b] { p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0]) }
        XCTAssertTrue(a.mesh.send(try wire("not for you", a)))
        XCTAssertTrue(b.groups.chatMessages(groupID: b.groups.groups[0].id).isEmpty)
    }

    func testLicensedRadioNeverSends() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1, licensed: true)
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertTrue(p.mesh.licensed)
        XCTAssertFalse(p.mesh.isReady)
        let before = p.radio.written.count
        XCTAssertFalse(p.mesh.send(try wire("hello", p)))
        XCTAssertEqual(p.radio.written.count, before, "nothing written to a ham-mode radio")
        XCTAssertNotNil(p.mesh.problem)
    }

    func testTooLongForOnePacketIsRefused() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1)
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertFalse(p.mesh.send(Data(count: Meshtastic.maxPayload + 1)))
        XCTAssertEqual(p.mesh.problem, "Too long for the radio. Shorten the message to send it by radio.")
    }

    func testSentByRadioIsRecordedThatWayWhenOffline() async throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1)
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        let w = try wire("by radio", p)
        XCTAssertTrue(p.mesh.send(w))
        _ = await p.online.send(wire: w, keySet: p.groups.keySets().first { $0.room == "" }!, sentBy: "radio")
        XCTAssertEqual(p.groups.chatMessages(groupID: p.groups.groups[0].id).first?.via, "radio", "not 'waiting for a connection'")
    }

    func testNewRadioWaitsForTheRegionThenGetsItAfterConfirming() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1) { $0.region = 0 }
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertTrue(p.mesh.regionUnset)
        XCTAssertFalse(p.mesh.isReady, "a radio with no region cannot transmit")
        XCTAssertFalse(p.mesh.send(try wire("hello", p)))
        XCTAssertEqual(p.radio.region, 0, "nothing changes until the person confirms")
        XCTAssertEqual(p.mesh.suggestedRegion?.code, 1)
        p.mesh.setSuggestedRegion()
        XCTAssertEqual(p.radio.region, 1)
        XCTAssertFalse(p.mesh.regionUnset)
        XCTAssertTrue(p.mesh.isReady)
    }

    func testRegionIsNeverGuessedForAnUnknownCountryOrChanged() throws {
        let unknown = try phone(try Phrase.generate(words: 10), node: 0xA1, country: "BR") { $0.region = 0 }
        unknown.mesh.setOn(true); unknown.mesh.choose(unknown.mesh.radios[0])
        XCTAssertNil(unknown.mesh.suggestedRegion)
        unknown.mesh.setSuggestedRegion()
        XCTAssertEqual(unknown.radio.region, 0)
        // A radio that already has a region keeps it.
        let set = try phone(try Phrase.generate(words: 10), node: 0xB2) { $0.region = 3 }
        set.mesh.setOn(true); set.mesh.choose(set.mesh.radios[0])
        XCTAssertFalse(set.mesh.regionUnset)
        set.mesh.setSuggestedRegion()
        XCTAssertEqual(set.radio.region, 3)
    }

    func testLocationSharingIsTurnedOffOnPairing() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1) { $0.gpsOn = true; $0.precision = 13 }
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertFalse(p.radio.gpsOn)
        XCTAssertEqual(p.radio.precision, 0)
        XCTAssertEqual(p.mesh.locationNote, "Location sharing turned off on this radio.")
        XCTAssertTrue(p.mesh.isReady)
    }

    func testRadioThatKeepsSharingIsReportedNotRetriedForever() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1) { $0.gpsOn = true; $0.ignoresAdmin = true }
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertEqual(p.radio.adminCount, 3, "one batch: begin, position, commit")
        XCTAssertTrue(p.mesh.locationNote?.contains("could not turn off") ?? false)
    }

    func testNoSettingsChangeForARadioAlreadyPrivate() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1) { $0.region = 1 }
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertEqual(p.radio.adminCount, 0)
        XCTAssertNil(p.mesh.locationNote)
    }

    func testCollectsOtherRadiosItHearsForTheMeshMap() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1)
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        XCTAssertTrue(p.mesh.nodes.isEmpty, "its own node is not listed")
        // Another radio broadcasts where it is (POSITION_APP), then its names (NODEINFO_APP).
        func heard(from: UInt32, port: Int, _ payload: Data) {
            var data = Meshtastic.Writer(); data.varint(field: 1, UInt64(port)); data.bytes(field: 2, payload)
            var packet = Meshtastic.Writer(); packet.fixed32(field: 1, from); packet.bytes(field: 4, data.data)
            var out = Meshtastic.Writer(); out.bytes(field: 2, packet.data)
            p.radio.onFrame?(out.data)
        }
        var position = Meshtastic.Writer()
        position.fixed32(field: 1, UInt32(bitPattern: Int32(377_749_000))); position.fixed32(field: 2, UInt32(bitPattern: Int32(-1_224_194_000)))
        heard(from: 0xC3, port: Meshtastic.positionPort, position.data)
        var user = Meshtastic.Writer(); user.bytes(field: 2, Data("Hilltop".utf8))
        heard(from: 0xC3, port: Meshtastic.nodeInfoPort, user.data)
        let node = try XCTUnwrap(p.mesh.nodes[0xC3])
        XCTAssertEqual(node.displayName, "Hilltop")
        XCTAssertEqual(node.latitude!, 37.7749, accuracy: 1e-6)
        XCTAssertNotNil(node.lastHeard)
        p.mesh.wipe()
        XCTAssertTrue(p.mesh.nodes.isEmpty, "wipe forgets them")
    }

    func testWipeForgetsTheRadio() throws {
        let p = try phone(try Phrase.generate(words: 10), node: 0xA1)
        p.mesh.setOn(true); p.mesh.choose(p.mesh.radios[0])
        p.mesh.wipe()
        XCTAssertFalse(p.mesh.isOn)
        XCTAssertNil(p.mesh.savedRadio)
        XCTAssertEqual(p.mesh.status, .off)
        var made = false
        let after = MeshtasticModel(defaults: p.defaults) { made = true; return FakeRadio(node: 1) }
        after.startIfWanted()
        XCTAssertFalse(after.isOn, "a wipe leaves the radio off, not back on its default")
        XCTAssertFalse(made)
    }
}
