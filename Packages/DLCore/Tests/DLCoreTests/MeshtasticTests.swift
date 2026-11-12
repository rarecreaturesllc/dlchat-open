import XCTest
@testable import DLCore

final class MeshtasticTests: XCTestCase {
    func testWantConfigBytes() {
        XCTAssertEqual([UInt8](Meshtastic.wantConfig(id: 1)), [0x18, 0x01])
        XCTAssertEqual([UInt8](Meshtastic.wantConfig(id: 300)), [0x18, 0xAC, 0x02])
    }

    /// ToRadio.disconnect is field 4, a bool: tag (4 << 3 | varint) = 0x20, then 1.
    func testDisconnectBytes() {
        XCTAssertEqual([UInt8](Meshtastic.disconnect), [0x20, 0x01])
    }

    /// Worked out by hand from the field numbers: ToRadio.packet(1) { to(2) fixed32, decoded(4) {
    /// portnum(1)=256, payload(2) }, id(6) fixed32, hop_limit(9)=3 }.
    func testBroadcastPacketBytes() throws {
        let bytes = [UInt8](try Meshtastic.broadcastPacket(payload: Data([0xAA]), id: 0x0102_0304))
        XCTAssertEqual(bytes, [0x0A, 0x14,
                               0x15, 0xFF, 0xFF, 0xFF, 0xFF,
                               0x22, 0x06, 0x08, 0x80, 0x02, 0x12, 0x01, 0xAA,
                               0x35, 0x04, 0x03, 0x02, 0x01,
                               0x48, 0x03])
    }

    func testSizeLimits() {
        XCTAssertThrowsError(try Meshtastic.broadcastPacket(payload: Data(count: 234), id: 1))
        XCTAssertThrowsError(try Meshtastic.broadcastPacket(payload: Data(), id: 1))
        XCTAssertNoThrow(try Meshtastic.broadcastPacket(payload: Data(count: 233), id: 1))
    }

    /// A received packet is a FromRadio.packet(2) carrying from(1); build one with our writer.
    func testParsesAReceivedPacket() {
        var data = Meshtastic.Writer(); data.varint(field: 1, 256); data.bytes(field: 2, Data([1, 2, 3]))
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, 0xDEAD_BEEF); packet.fixed32(field: 2, Meshtastic.broadcast)
        packet.bytes(field: 4, data.data); packet.fixed32(field: 6, 7); packet.varint(field: 9, 2)
        var from = Meshtastic.Writer(); from.varint(field: 1, 42); from.bytes(field: 2, packet.data)
        XCTAssertEqual(Meshtastic.parse(from.data), .packet(from: 0xDEAD_BEEF, port: 256, payload: Data([1, 2, 3])))
    }

    func testEncryptedPacketIsOther() {
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, 5); packet.bytes(field: 5, Data([9, 9]))
        var from = Meshtastic.Writer(); from.bytes(field: 2, packet.data)
        XCTAssertEqual(Meshtastic.parse(from.data), .other)
    }

    func testParsesHandshakeAndLicensedFlag() {
        var my = Meshtastic.Writer(); my.varint(field: 1, 0x1234_5678)
        var f1 = Meshtastic.Writer(); f1.bytes(field: 3, my.data)
        XCTAssertEqual(Meshtastic.parse(f1.data), .myInfo(nodeNum: 0x1234_5678))

        var user = Meshtastic.Writer(); user.bytes(field: 1, Data("!12345678".utf8))
        user.bytes(field: 2, Data("Porch radio".utf8)); user.bytes(field: 3, Data("PR".utf8)); user.varint(field: 6, 1)
        var node = Meshtastic.Writer(); node.varint(field: 1, 0x1234_5678); node.bytes(field: 2, user.data); node.varint(field: 9, 0)
        var f2 = Meshtastic.Writer(); f2.bytes(field: 4, node.data)
        XCTAssertEqual(Meshtastic.parse(f2.data), .nodeInfo(num: 0x1234_5678, longName: "Porch radio", shortName: "PR", isLicensed: true))

        var f3 = Meshtastic.Writer(); f3.varint(field: 7, 99)
        XCTAssertEqual(Meshtastic.parse(f3.data), .configComplete(id: 99))
        var f4 = Meshtastic.Writer(); f4.varint(field: 1, 3); f4.varint(field: 8, 1)
        XCTAssertEqual(Meshtastic.parse(f4.data), .rebooted)
    }

    func testSkipsUnknownFieldsAndRejectsGarbage() {
        var f = Meshtastic.Writer(); f.varint(field: 1, 5); f.bytes(field: 11, Data([1, 2])); f.fixed32(field: 13, 1)
        XCTAssertEqual(Meshtastic.parse(f.data), .other)
        XCTAssertNil(Meshtastic.parse(Data([0x12, 0x05, 0x01])))  // length runs past the end
        XCTAssertNil(Meshtastic.parse(Data([0x0B])))              // group wire type
        XCTAssertNil(Meshtastic.parse(Data([0x80])))              // varint never ends
    }

    /// A radio (or a fake one) can send any 64-bit number where a small one is expected.
    func testHugeNumbersFromARadioAreClampedNotACrash() {
        var decoded = Meshtastic.Writer(); decoded.varint(field: 1, .max); decoded.bytes(field: 2, Data([1]))
        var packet = Meshtastic.Writer(); packet.fixed32(field: 1, 7); packet.bytes(field: 4, decoded.data)
        packet.varint(field: 9, 0); packet.varint(field: 15, .max)
        var from = Meshtastic.Writer(); from.bytes(field: 2, packet.data)
        guard case .packet(7, let port, _)? = Meshtastic.parse(from.data) else { return XCTFail("not a packet") }
        XCTAssertEqual(port, Int.max)
        XCTAssertEqual(Meshtastic.packet(fromRadio: from.data)?.port, Int.max)
        XCTAssertEqual(Meshtastic.packet(fromRadio: from.data)?.hops, Int.max)

        var node = Meshtastic.Writer(); node.varint(field: 1, 5); node.varint(field: 9, .max)
        var info = Meshtastic.Writer(); info.bytes(field: 4, node.data)
        XCTAssertEqual(Meshtastic.meshNode(fromNodeInfo: info.data)?.hops, Int.max)

        var lora = Meshtastic.Writer(); lora.varint(field: 1, 1); lora.varint(field: 2, .max)
        XCTAssertNil(Meshtastic.presetName(currentLoRa: lora.data))

        // Field number 2^29 (one past protobuf's largest), wire type 0, value 0.
        XCTAssertNil(Meshtastic.Reader.fields(Data([0x80, 0x80, 0x80, 0x80, 0x10, 0x00])))
        // The largest real field number still reads.
        XCTAssertEqual(Meshtastic.Reader.fields(Data([0xF8, 0xFF, 0xFF, 0xFF, 0x0F, 0x00]))?.first?.number, (1 << 29) - 1)
    }

    func testRoundTripsADLChatWire() throws {
        let keys = Keys(phrase: try Phrase.generate(words: 10))
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: "need water at north gate", keys: keys), ttl: 0)
        XCTAssertLessThanOrEqual(wire.count, Meshtastic.maxPayload, "a short message fits one packet")
        let out = try Meshtastic.broadcastPacket(payload: wire, id: 9)
        // The radio echoes our packet back as FromRadio.packet; same MeshPacket bytes.
        let packet = try XCTUnwrap(Meshtastic.Reader.fields(out)?.bytes(1))
        var from = Meshtastic.Writer(); from.bytes(field: 2, packet)
        guard case .packet(_, 256, let payload)? = Meshtastic.parse(from.data) else { return XCTFail() }
        XCTAssertEqual(Receiver.readNearby(wire: payload, trying: [keys])?.text, "need water at north gate")
    }

    // MARK: Radio settings

    private func fromRadioConfig(_ field: Int, _ sub: Data) -> Data {
        var config = Meshtastic.Writer(); config.bytes(field: field, sub)
        var from = Meshtastic.Writer(); from.bytes(field: 5, config.data)
        return from.data
    }

    /// The admin payload inside a ToRadio packet built by `adminPacket`.
    private func admin(_ toRadio: Data) throws -> [Meshtastic.Field] {
        let packet = try XCTUnwrap(Meshtastic.Reader.fields(toRadio)?.bytes(1).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(packet.fixed32(2), 0xA1, "addressed to the radio itself")
        let data = try XCTUnwrap(packet.bytes(4).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(data.varint(1), 6, "ADMIN_APP port")
        return try XCTUnwrap(data.bytes(2).flatMap(Meshtastic.Reader.fields))
    }

    func testReadsRegionAndKeepsOtherLoRaSettingsWhenSettingIt() throws {
        // A new radio: use_preset, tx_enabled, hop_limit 3, region unset, plus a field DLChat does not know.
        var lora = Meshtastic.Writer()
        lora.varint(field: 1, 1); lora.varint(field: 8, 3); lora.varint(field: 9, 1); lora.varint(field: 999, 42)
        guard case .loraConfig(let raw, let region) = Meshtastic.parse(fromRadioConfig(6, lora.data)) else { return XCTFail() }
        XCTAssertEqual(region, 0)
        let fields = try admin(Meshtastic.adminPacket(Meshtastic.setRegion(1, currentLoRa: raw), to: 0xA1, id: 7))
        let sent = try XCTUnwrap(fields.bytes(34).flatMap(Meshtastic.Reader.fields)?.bytes(6).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(sent.lastVarint(7), 1, "region US")
        XCTAssertEqual(sent.lastVarint(9), 1, "still allowed to transmit")
        XCTAssertEqual(sent.lastVarint(8), 3)
        XCTAssertEqual(sent.lastVarint(999), 42, "unknown settings pass through")
    }

    func testSendsWithTheRadiosHopLimit() {
        func lora(hops: UInt64) -> Data { var w = Meshtastic.Writer(); w.varint(field: 1, 1); w.varint(field: 8, hops); return w.data }
        XCTAssertEqual(Meshtastic.hopLimit(currentLoRa: lora(hops: 5)), 5)
        XCTAssertEqual(Meshtastic.hopLimit(currentLoRa: lora(hops: 9)), 3, "out of range")
        XCTAssertEqual(Meshtastic.hopLimit(currentLoRa: Data()), 3, "unset")
        XCTAssertEqual(Meshtastic.hopLimit(currentLoRa: nil), 3, "settings not read yet")
    }

    func testLocationOffWritesExplicitZeros() throws {
        var position = Meshtastic.Writer()
        position.varint(field: 1, 900); position.varint(field: 2, 1); position.varint(field: 13, Meshtastic.GPSMode.enabled)
        guard case .positionConfig(let raw, let shares) = Meshtastic.parse(fromRadioConfig(2, position.data)) else { return XCTFail() }
        XCTAssertTrue(shares)
        let fields = try admin(Meshtastic.adminPacket(Meshtastic.locationOff(currentPosition: raw), to: 0xA1, id: 7))
        let sentRaw = try XCTUnwrap(fields.bytes(34).flatMap(Meshtastic.Reader.fields)?.bytes(2))
        let sent = try XCTUnwrap(Meshtastic.Reader.fields(sentRaw))
        XCTAssertEqual(sent.lastVarint(13), Meshtastic.GPSMode.disabled)
        XCTAssertEqual(sent.lastVarint(3), 0)
        XCTAssertEqual(sent.lastVarint(2), 0)
        XCTAssertEqual(sent.lastVarint(1), 900, "other position settings kept")
        guard case .positionConfig(_, let after) = Meshtastic.parse(fromRadioConfig(2, sentRaw)) else { return XCTFail() }
        XCTAssertFalse(after)
    }

    func testChannelLosesPositionButKeepsItsKey() throws {
        var module = Meshtastic.Writer(); module.varint(field: 1, 13)
        var settings = Meshtastic.Writer(); settings.bytes(field: 2, Data([1])); settings.bytes(field: 7, module.data)
        var channel = Meshtastic.Writer(); channel.varint(field: 1, 0); channel.bytes(field: 2, settings.data); channel.varint(field: 3, 1)
        var from = Meshtastic.Writer(); from.bytes(field: 10, channel.data)
        guard case .channel(let raw, 0, 13) = Meshtastic.parse(from.data) else { return XCTFail() }
        let fields = try admin(Meshtastic.adminPacket(try XCTUnwrap(Meshtastic.channelWithoutPosition(currentChannel: raw)), to: 0xA1, id: 7))
        let sent = try XCTUnwrap(fields.bytes(33).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(sent.lastVarint(3), 1, "role kept")
        let st = try XCTUnwrap(sent.lastBytes(2).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(st.lastBytes(2), Data([1]), "channel key kept")
        XCTAssertEqual(st.lastBytes(7).flatMap(Meshtastic.Reader.fields)?.lastVarint(1), 0)
    }

    func testRegionComesOnlyFromKnownCountries() {
        XCTAssertEqual(Meshtastic.region(forCountry: "US")?.code, 1)
        XCTAssertEqual(Meshtastic.region(forCountry: "de")?.code, 3)
        XCTAssertNil(Meshtastic.region(forCountry: "BR"), "unknown: left to the person, never guessed")
    }
}
