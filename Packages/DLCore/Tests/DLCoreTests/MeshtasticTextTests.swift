import XCTest
@testable import DLCore

final class MeshtasticTextTests: XCTestCase {
    /// Worked out by hand: ToRadio.packet(1) { to(2) fixed32 broadcast, channel(3)=1, decoded(4) { portnum(1)=1,
    /// payload(2)="hi" }, id(6) fixed32, hop_limit(9)=3, want_ack(10)=1 }. No pki_encrypted on a channel message.
    func testChannelTextBytes() throws {
        let bytes = [UInt8](try Meshtastic.textPacket("hi", to: Meshtastic.broadcast, channel: 1, id: 0x0102_0304))
        XCTAssertEqual(bytes, [0x0A, 0x18,
                               0x15, 0xFF, 0xFF, 0xFF, 0xFF,
                               0x18, 0x01,
                               0x22, 0x06, 0x08, 0x01, 0x12, 0x02, 0x68, 0x69,
                               0x35, 0x04, 0x03, 0x02, 0x01,
                               0x48, 0x03,
                               0x50, 0x01])
    }

    /// A direct message is marked pki_encrypted (17) so the radio fails rather than use a channel key,
    /// and carries the recipient's public key (16) when DLChat has it. It never names a channel.
    func testDirectTextIsMarkedForPublicKeyEncryption() throws {
        let key = Data(repeating: 7, count: 32)
        let out = try Meshtastic.textPacket("hello", to: 0xC3, channel: 2, id: 9, publicKey: key)
        let p = try XCTUnwrap(Meshtastic.Reader.fields(out)?.bytes(1).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(p.fixed32(2), 0xC3)
        XCTAssertNil(p.varint(3), "no channel index on a direct message")
        XCTAssertEqual(p.varint(17), 1)
        XCTAssertEqual(p.bytes(16), key)
        XCTAssertEqual(p.varint(10), 1, "want_ack, so delivery is reported")
        let d = try XCTUnwrap(p.bytes(4).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(d.varint(1), UInt64(Meshtastic.textPort))
        XCTAssertEqual(d.string(2), "hello")
        // A key of the wrong size is left out; the radio uses the one it knows, or refuses.
        let noKey = try Meshtastic.textPacket("hello", to: 0xC3, id: 9, publicKey: Data([1, 2]))
        XCTAssertNil(Meshtastic.Reader.fields(noKey)?.bytes(1).flatMap(Meshtastic.Reader.fields)?.bytes(16))
    }

    func testTextSizeIsCountedInBytes() {
        XCTAssertNoThrow(try Meshtastic.textPacket(String(repeating: "a", count: 200), to: Meshtastic.broadcast, id: 1))
        XCTAssertThrowsError(try Meshtastic.textPacket(String(repeating: "a", count: 201), to: Meshtastic.broadcast, id: 1))
        XCTAssertThrowsError(try Meshtastic.textPacket(String(repeating: "é", count: 101), to: Meshtastic.broadcast, id: 1), "202 bytes")
        XCTAssertThrowsError(try Meshtastic.textPacket("", to: Meshtastic.broadcast, id: 1))
    }

    func testParsesAReceivedTextPacket() throws {
        var data = Meshtastic.Writer(); data.varint(field: 1, 1); data.bytes(field: 2, Data("hey all".utf8))
        var packet = Meshtastic.Writer()
        packet.fixed32(field: 1, 0xC3); packet.fixed32(field: 2, 0xA1); packet.varint(field: 3, 0)
        packet.bytes(field: 4, data.data); packet.fixed32(field: 6, 77); packet.fixed32(field: 7, 1_700_000_000)
        packet.varint(field: 9, 1); packet.varint(field: 15, 3); packet.varint(field: 17, 1)
        var from = Meshtastic.Writer(); from.varint(field: 1, 5); from.bytes(field: 2, packet.data)
        let p = try XCTUnwrap(Meshtastic.packet(fromRadio: from.data))
        XCTAssertEqual(p.from, 0xC3)
        XCTAssertEqual(p.to, 0xA1)
        XCTAssertFalse(p.isBroadcast)
        XCTAssertEqual(p.id, 77)
        XCTAssertEqual(p.port, Meshtastic.textPort)
        XCTAssertEqual(String(decoding: p.payload, as: UTF8.self), "hey all")
        XCTAssertTrue(p.pkiEncrypted)
        XCTAssertEqual(p.hops, 2)
        XCTAssertEqual(p.received, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(Meshtastic.parse(from.data), .packet(from: 0xC3, port: 1, payload: Data("hey all".utf8)), "the old parse still sees it")
    }

    func testParsesAnAcknowledgement() throws {
        var routing = Meshtastic.Writer(); routing.varint(field: 3, 35)
        var data = Meshtastic.Writer(); data.varint(field: 1, 5); data.bytes(field: 2, routing.data); data.fixed32(field: 6, 0xABCD)
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, 0xA1); packet.bytes(field: 4, data.data)
        var from = Meshtastic.Writer(); from.bytes(field: 2, packet.data)
        let p = try XCTUnwrap(Meshtastic.packet(fromRadio: from.data))
        XCTAssertEqual(p.port, Meshtastic.routingPort)
        XCTAssertEqual(p.requestID, 0xABCD)
        XCTAssertEqual(Meshtastic.routingError(p.payload), 35)
        XCTAssertTrue(Meshtastic.routingProblem(35).contains("key"))
        XCTAssertEqual(Meshtastic.routingError(Data()), 0)
        XCTAssertTrue(Meshtastic.transmittedUnheard(5), "MAX_RETRANSMIT: sent, no repeat heard")
        for code: UInt64 in [0, 1, 6, 7, 9, 33, 35] { XCTAssertFalse(Meshtastic.transmittedUnheard(code), "code \(code)") }
    }

    func testEncryptedOrOtherFramesAreNotPackets() {
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, 5); packet.bytes(field: 5, Data([9, 9]))
        var from = Meshtastic.Writer(); from.bytes(field: 2, packet.data)
        XCTAssertNil(Meshtastic.packet(fromRadio: from.data))
        XCTAssertNil(Meshtastic.packet(fromRadio: Meshtastic.wantConfig(id: 1)))
    }

    func testCleansStrangersText() {
        XCTAssertEqual(Meshtastic.cleanText(Data("  hi\u{0007}\nthere\u{202E} ".utf8)), "hi\nthere", "bell and right-to-left override dropped, line break kept")
        XCTAssertEqual(Meshtastic.cleanText(Data([0x68, 0xFF, 0x69])), "h\u{FFFD}i", "bad UTF-8 is replaced, not trusted")
        XCTAssertEqual(Meshtastic.cleanText(Data(repeating: 0x61, count: 500)).count, Meshtastic.maxPayload)
    }

    func testChannelInfo() throws {
        func channel(index: UInt64, role: UInt64, psk: Data, name: String = "", uplink: Bool = false) -> Data {
            var settings = Meshtastic.Writer(); settings.bytes(field: 2, psk)
            if !name.isEmpty { settings.bytes(field: 3, Data(name.utf8)) }
            if uplink { settings.varint(field: 5, 1) }
            var ch = Meshtastic.Writer(); ch.varint(field: 1, index); ch.bytes(field: 2, settings.data); ch.varint(field: 3, role)
            return ch.data
        }
        let primary = try XCTUnwrap(Meshtastic.channelInfo(channel(index: 0, role: 1, psk: Data([1]))))
        XCTAssertTrue(primary.keyIsPublic, "the default key is published")
        XCTAssertEqual(primary.title(preset: "LongFast"), "LongFast")
        XCTAssertEqual(primary.title(preset: nil), "Primary channel")
        let none = try XCTUnwrap(Meshtastic.channelInfo(channel(index: 0, role: 1, psk: Data())))
        XCTAssertTrue(none.keyIsPublic, "no key at all")
        let privateOne = try XCTUnwrap(Meshtastic.channelInfo(channel(index: 1, role: 2, psk: Data(repeating: 3, count: 32), name: "Family", uplink: true)))
        XCTAssertFalse(privateOne.keyIsPublic)
        XCTAssertTrue(privateOne.uplink)
        XCTAssertEqual(privateOne.title(preset: "LongFast"), "Family")
        XCTAssertNil(Meshtastic.channelInfo(channel(index: 2, role: 0, psk: Data([1]))), "disabled slots are not listed")
    }

    func testPresetName() {
        var lora = Meshtastic.Writer(); lora.varint(field: 1, 1)
        XCTAssertEqual(Meshtastic.presetName(currentLoRa: lora.data), "LongFast", "modem_preset unset is LONG_FAST")
        lora.varint(field: 2, 4)
        XCTAssertEqual(Meshtastic.presetName(currentLoRa: lora.data), "MediumFast")
        var custom = Meshtastic.Writer(); custom.varint(field: 2, 4)
        XCTAssertNil(Meshtastic.presetName(currentLoRa: custom.data), "use_preset off: custom settings")
        XCTAssertNil(Meshtastic.presetName(currentLoRa: nil))
    }

    func testNodeInfoCarriesThePublicKey() throws {
        let key = Data(repeating: 9, count: 32)
        var user = Meshtastic.Writer(); user.bytes(field: 2, Data("Hilltop".utf8)); user.bytes(field: 3, Data("HILL".utf8)); user.bytes(field: 8, key)
        var info = Meshtastic.Writer(); info.varint(field: 1, 0xC3); info.bytes(field: 2, user.data)
        var from = Meshtastic.Writer(); from.bytes(field: 4, info.data)
        let node = try XCTUnwrap(Meshtastic.meshNode(fromNodeInfo: from.data))
        XCTAssertEqual(node.publicKey, key)
        XCTAssertEqual(node.shortName, "HILL")
    }
}
