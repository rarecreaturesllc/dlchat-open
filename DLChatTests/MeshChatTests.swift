import DLCore
import XCTest
@testable import DLChat

/// Plain Meshtastic chats (public channel and direct messages) between two pretend radios.
@MainActor
final class MeshChatTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() { suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }; suites = [] }

    private func radio(_ node: UInt32, licensed: Bool = false) -> (MeshtasticModel, FakeRadio) {
        let suite = "dlchat.meshchat.tests.\(UUID().uuidString)"
        suites.append(suite)
        let fake = FakeRadio(node: node)
        fake.licensed = licensed
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: MeshtasticModel.lawAcceptedKey)
        let mesh = MeshtasticModel(defaults: d, country: { "US" }) { fake }
        return (mesh, fake)
    }

    private func pair(_ a: (MeshtasticModel, FakeRadio), _ b: (MeshtasticModel, FakeRadio)) {
        a.1.air = [a.1, b.1]; b.1.air = a.1.air
        for (mesh, _) in [a, b] { mesh.setOn(true); mesh.choose(mesh.radios[0]) }
    }

    /// The radio announcing another radio's names and key (NODEINFO_APP).
    private func announce(_ num: UInt32, long: String, short: String, key: Data? = Data(repeating: 4, count: 32), to fake: FakeRadio) {
        var user = Meshtastic.Writer(); user.bytes(field: 2, Data(long.utf8)); user.bytes(field: 3, Data(short.utf8))
        if let key { user.bytes(field: 8, key) }
        var data = Meshtastic.Writer(); data.varint(field: 1, UInt64(Meshtastic.nodeInfoPort)); data.bytes(field: 2, user.data)
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, num); packet.fixed32(field: 2, Meshtastic.broadcast); packet.bytes(field: 4, data.data)
        var out = Meshtastic.Writer(); out.bytes(field: 2, packet.data)
        fake.onFrame?(out.data)
    }

    private func ack(_ requestID: UInt32, from: UInt32, error: UInt64 = 0, to fake: FakeRadio) {
        var routing = Meshtastic.Writer(); routing.varint(field: 3, error)
        var data = Meshtastic.Writer(); data.varint(field: 1, UInt64(Meshtastic.routingPort)); data.bytes(field: 2, routing.data); data.fixed32(field: 6, requestID)
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, from); packet.fixed32(field: 2, fake.node); packet.bytes(field: 4, data.data)
        var out = Meshtastic.Writer(); out.bytes(field: 2, packet.data)
        fake.onFrame?(out.data)
    }

    func testListsTheRadiosPublicChannel() {
        let (mesh, _) = radio(0xA1)
        mesh.setOn(true); mesh.choose(mesh.radios[0])
        XCTAssertEqual(mesh.channels.map(\.index), [0])
        XCTAssertTrue(mesh.channels[0].keyIsPublic, "the default key is the public one")
        XCTAssertEqual(mesh.title(of: .channel(0)), "Primary channel", "no LoRa settings arrived, so no preset name")
    }

    func testPublicChannelMessageReachesTheOtherRadioWithItsSendersName() {
        let a = radio(0xA1), b = radio(0xB2)
        pair(a, b)
        announce(0xA1, long: "Porch radio", short: "PRCH", to: b.1)
        XCTAssertNil(a.0.sendText("anyone on?", in: .channel(0)))
        let got = b.0.texts[.channel(0)] ?? []
        XCTAssertEqual(got.map(\.text), ["anyone on?"])
        XCTAssertEqual(got.first?.from, 0xA1)
        XCTAssertEqual(b.0.unread[.channel(0)], 1)
        XCTAssertEqual(a.0.texts[.channel(0)]?.first?.outgoing, true)
        XCTAssertNil(a.0.unread[.channel(0)], "our own message is not unread")
    }

    func testDirectMessageGoesOnlyToThatRadioAndAsksForPublicKeyEncryption() throws {
        let a = radio(0xA1), b = radio(0xB2), c = radio(0xC3)
        a.1.air = [a.1, b.1, c.1]; b.1.air = a.1.air; c.1.air = a.1.air
        for (mesh, _) in [a, b, c] { mesh.setOn(true); mesh.choose(mesh.radios[0]) }
        announce(0xB2, long: "Hilltop", short: "HILL", to: a.1)
        XCTAssertEqual(a.0.directNodes.map(\.displayName), ["Hilltop"])
        XCTAssertNil(a.0.sendText("just you", in: .direct(0xB2)))
        let sent = try XCTUnwrap(a.1.written.last.flatMap { Meshtastic.Reader.fields($0)?.bytes(1) }.flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(sent.fixed32(2), 0xB2)
        XCTAssertEqual(sent.varint(17), 1, "pki_encrypted: fail rather than fall back to the channel key")
        XCTAssertEqual(sent.bytes(16)?.count, 32, "the key the radio announced")
        XCTAssertEqual(b.0.texts[.direct(0xA1)]?.map(\.text), ["just you"])
        XCTAssertNil(c.0.texts[.direct(0xA1)], "a third radio does not show someone else's direct message")
        XCTAssertTrue(c.0.texts.isEmpty)
    }

    func testDeliveryIsReportedFromTheAcknowledgement() throws {
        let (mesh, fake) = radio(0xA1)
        mesh.setOn(true); mesh.choose(mesh.radios[0])
        XCTAssertNil(mesh.sendText("ping", in: .direct(0xB2)))
        let id = try XCTUnwrap(mesh.texts[.direct(0xB2)]?.last?.packetID)
        XCTAssertEqual(mesh.texts[.direct(0xB2)]?.last?.state, .sending)
        ack(id, from: 0xA1, to: fake)
        XCTAssertEqual(mesh.texts[.direct(0xB2)]?.last?.state, .relayed, "our own radio heard it passed on")
        ack(id, from: 0xB2, to: fake)
        XCTAssertEqual(mesh.texts[.direct(0xB2)]?.last?.state, .delivered)
        XCTAssertNil(mesh.sendText("again", in: .direct(0xB2)))
        let second = try XCTUnwrap(mesh.texts[.direct(0xB2)]?.last?.packetID)
        ack(second, from: 0xA1, error: 35, to: fake)
        guard case .failed(let why) = mesh.texts[.direct(0xB2)]?.last?.state else { return XCTFail("should have failed") }
        XCTAssertTrue(why.contains("key"))
    }

    func testRepeatsFromTheMeshShowOnce() {
        let a = radio(0xA1), b = radio(0xB2)
        pair(a, b)
        XCTAssertNil(a.0.sendText("once", in: .channel(0)))
        // The same packet heard again through another hop.
        b.1.onFrame?(Self.reheard(a.1.written.last!, from: 0xA1))
        XCTAssertEqual(b.0.texts[.channel(0)]?.count, 1)
    }

    private static func reheard(_ toRadio: Data, from: UInt32) -> Data {
        var p = Meshtastic.Writer(); p.fixed32(field: 1, from)
        for f in Meshtastic.Reader.fields(Meshtastic.Reader.fields(toRadio)!.bytes(1)!)! { p.field(f) }
        var out = Meshtastic.Writer(); out.bytes(field: 2, p.data)
        return out.data
    }

    func testLicensedRadioSendsOnTheChannelButNotPrivately() {
        let (mesh, fake) = radio(0xA1, licensed: true)
        mesh.setOn(true); mesh.choose(mesh.radios[0])
        let before = fake.written.count
        XCTAssertNotNil(mesh.sendText("private", in: .direct(0xB2)))
        XCTAssertEqual(fake.written.count, before, "nothing written: ham mode forbids encryption")
        XCTAssertNil(mesh.sendText("public hello", in: .channel(0)), "plain channel text is allowed in licensed mode")
    }

    func testRefusesWhatMeshtasticCannotCarry() {
        let (mesh, _) = radio(0xA1)
        XCTAssertNotNil(mesh.sendText("hi", in: .channel(0)), "radio not connected")
        mesh.setOn(true); mesh.choose(mesh.radios[0])
        XCTAssertTrue(mesh.sendText(String(repeating: "a", count: 201), in: .channel(0))?.contains("201 of 200") ?? false)
        XCTAssertNotNil(mesh.sendText("hi", in: .channel(5)), "a channel the radio does not have")
        XCTAssertNil(mesh.sendText("   ", in: .channel(0)))
        XCTAssertNil(mesh.texts[.channel(0)], "nothing recorded for refused or empty messages")
    }

    func testOpenConversationIsReadAndWipeForgetsEverything() {
        let a = radio(0xA1), b = radio(0xB2)
        pair(a, b)
        b.0.openConversation(.direct(0xA1))
        b.0.setViewing(true)
        XCTAssertNil(a.0.sendText("seen", in: .direct(0xB2)))
        XCTAssertNil(b.0.unread[.direct(0xA1)], "on screen, so not unread")
        b.0.setViewing(false)
        XCTAssertNil(a.0.sendText("later", in: .direct(0xB2)))
        XCTAssertEqual(b.0.unreadDirect, 1)
        b.0.wipe()
        XCTAssertTrue(b.0.texts.isEmpty)
        XCTAssertTrue(b.0.unread.isEmpty)
        XCTAssertNil(b.0.open)
        XCTAssertTrue(b.0.channels.isEmpty)
    }
}
