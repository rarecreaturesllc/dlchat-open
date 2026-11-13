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

    // MARK: Radio settings writers

    /// A LoRa section as a radio sends it: region EU, a frequency slot, duty-cycle override, frequency
    /// override and offset, and a field DLChat does not know.
    private func radioLoRa() -> Data {
        var w = Meshtastic.Writer()
        w.varint(field: 1, 1); w.varint(field: 2, 0); w.fixed32(field: 6, 0x3F80_0000); w.varint(field: 7, 3)
        w.varint(field: 8, 3); w.varint(field: 9, 1); w.varint(field: 11, 20); w.varint(field: 12, 1)
        w.fixed32(field: 14, 0x4464_4000); w.varint(field: 999, 42)
        return w.data
    }

    /// The section sent in AdminMessage.set_config (34) -> Config.<section>.
    private func sentConfig(_ admin: Data, section: Int) throws -> [Meshtastic.Field] {
        let fields = try self.admin(Meshtastic.adminPacket(admin, to: 0xA1, id: 7))
        let config = try XCTUnwrap(fields.bytes(34).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(config.count, 1, "one section only")
        return try XCTUnwrap(config.bytes(section).flatMap(Meshtastic.Reader.fields))
    }

    /// Every field but `changed` goes back exactly as the radio sent it, so region, frequency slot, duty-cycle and
    /// frequency overrides are never altered.
    private func assertKept(_ sent: [Meshtastic.Field], from raw: Data, except changed: Set<Int>,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try XCTUnwrap(Meshtastic.Reader.fields(raw)).filter { !changed.contains($0.number) }
        XCTAssertEqual(sent.filter { !changed.contains($0.number) }, before, file: file, line: line)
    }

    private func encode(_ fields: [Meshtastic.Field]) -> Data {
        var w = Meshtastic.Writer(); fields.forEach { w.field($0) }; return w.data
    }

    func testTxPowerZeroMeansRegionMaximumAndKeepsTheRest() throws {
        let raw = radioLoRa()
        XCTAssertEqual(Meshtastic.txPower(currentLoRa: raw), 0)
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setTxPower(17, currentLoRa: raw)), section: 6)
        XCTAssertEqual(sent.lastVarint(10), 17)
        try assertKept(sent, from: raw, except: [10])
        XCTAssertEqual(try sentConfig(try XCTUnwrap(Meshtastic.setTxPower(0, currentLoRa: raw)), section: 6).lastVarint(10), 0,
                       "0 written out, so it replaces a lower power")
        XCTAssertNil(Meshtastic.setTxPower(31, currentLoRa: raw))
        XCTAssertNil(Meshtastic.setTxPower(-1, currentLoRa: raw))
    }

    func testHopLimit() throws {
        let raw = radioLoRa()
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setHopLimit(5, currentLoRa: raw)), section: 6)
        XCTAssertEqual(sent.lastVarint(8), 5)
        try assertKept(sent, from: raw, except: [8])
        XCTAssertNil(Meshtastic.setHopLimit(0, currentLoRa: raw))
        XCTAssertNil(Meshtastic.setHopLimit(8, currentLoRa: raw))
    }

    func testModemPresetNeverTouchesRegionOrFrequency() throws {
        var manual = Meshtastic.Writer(); manual.varint(field: 3, 250); manual.varint(field: 7, 1); manual.varint(field: 11, 5)
        XCTAssertNil(Meshtastic.modemPreset(currentLoRa: manual.data), "manual bandwidth, no preset")
        let raw = radioLoRa()
        XCTAssertEqual(Meshtastic.modemPreset(currentLoRa: raw), 0)
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setModemPreset(4, currentLoRa: raw)), section: 6)
        XCTAssertEqual(sent.lastVarint(1), 1)
        XCTAssertEqual(sent.lastVarint(2), 4)
        try assertKept(sent, from: raw, except: [1, 2])
        XCTAssertEqual(Meshtastic.presetName(currentLoRa: encode(sent)), "MediumFast")
        XCTAssertNil(Meshtastic.setModemPreset(1, currentLoRa: raw), "deprecated LONG_SLOW")
        XCTAssertNil(Meshtastic.setModemPreset(12, currentLoRa: raw), "newer region-limited preset")
    }

    func testMQTTFlags() throws {
        let raw = radioLoRa()
        XCTAssertFalse(Meshtastic.mqtt(currentLoRa: raw).okToMQTT)
        let sent = try sentConfig(Meshtastic.setMQTT(okToMQTT: false, ignoreMQTT: true, currentLoRa: raw), section: 6)
        XCTAssertEqual(sent.lastVarint(105), 0)
        XCTAssertEqual(sent.lastVarint(104), 1)
        try assertKept(sent, from: raw, except: [104, 105])
        XCTAssertTrue(Meshtastic.mqtt(currentLoRa: encode(sent)).ignoreMQTT)
    }

    func testLoRaWritersNeverEmitForbiddenFields() throws {
        let raw = Data()  // a radio that sent nothing: anything forbidden in the output came from DLChat
        let admins: [Data] = [Meshtastic.setTxPower(20, currentLoRa: raw)!, Meshtastic.setHopLimit(2, currentLoRa: raw)!,
                              Meshtastic.setModemPreset(7, currentLoRa: raw)!, Meshtastic.setMQTT(okToMQTT: true, ignoreMQTT: true, currentLoRa: raw)]
        for admin in admins {
            let sent = try sentConfig(admin, section: 6)
            XCTAssertTrue(sent.allSatisfy { !Meshtastic.forbiddenLoRaFields.contains($0.number) })
        }
    }

    private func radioDevice(role: UInt64, rebroadcast: UInt64) -> Data {
        var w = Meshtastic.Writer(); w.varint(field: 1, role); w.varint(field: 6, rebroadcast); w.varint(field: 7, 10800)
        w.bytes(field: 11, Data("EST5EDT".utf8))
        return w.data
    }

    func testRoleKeepsOtherDeviceSettings() throws {
        var f = Meshtastic.Writer(); f.bytes(field: 1, radioDevice(role: 0, rebroadcast: 0))
        var from = Meshtastic.Writer(); from.bytes(field: 5, f.data)
        guard case .deviceConfig(let raw) = Meshtastic.parse(from.data) else { return XCTFail() }
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setRole(Meshtastic.Role.clientMute, currentDevice: raw)), section: 1)
        XCTAssertEqual(sent.lastVarint(1), 1)
        try assertKept(sent, from: raw, except: [1])
        XCTAssertNil(Meshtastic.setRole(2, currentDevice: raw), "router is not offered")
        // Leaving Tracker with relaying off: NONE is not allowed for Client, so relaying goes back to ALL.
        let tracker = radioDevice(role: 5, rebroadcast: 4)
        let back = try sentConfig(try XCTUnwrap(Meshtastic.setRole(Meshtastic.Role.client, currentDevice: tracker)), section: 1)
        XCTAssertEqual(back.lastVarint(1), 0)
        XCTAssertEqual(back.lastVarint(6), 0)
        try assertKept(back, from: tracker, except: [1, 6])
    }

    func testRebroadcastMode() throws {
        let raw = radioDevice(role: 0, rebroadcast: 0)
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setRebroadcastMode(Meshtastic.Rebroadcast.localOnly, currentDevice: raw)), section: 1)
        XCTAssertEqual(sent.lastVarint(6), 2)
        try assertKept(sent, from: raw, except: [6])
        XCTAssertNil(Meshtastic.setRebroadcastMode(Meshtastic.Rebroadcast.none, currentDevice: raw), "NONE only for Tracker")
        XCTAssertNil(Meshtastic.setRebroadcastMode(1, currentDevice: raw), "ALL_SKIP_DECODING is for Repeater")
        XCTAssertNotNil(Meshtastic.setRebroadcastMode(Meshtastic.Rebroadcast.none, currentDevice: radioDevice(role: 5, rebroadcast: 0)))
    }

    func testPowerSaving() throws {
        var w = Meshtastic.Writer(); w.varint(field: 2, 300); w.varint(field: 4, 60)
        var f = Meshtastic.Writer(); f.bytes(field: 3, w.data)
        var from = Meshtastic.Writer(); from.bytes(field: 5, f.data)
        guard case .powerConfig(let raw) = Meshtastic.parse(from.data) else { return XCTFail() }
        XCTAssertFalse(Meshtastic.powerSaving(currentPower: raw))
        let sent = try sentConfig(Meshtastic.setPowerSaving(true, currentPower: raw), section: 3)
        XCTAssertEqual(sent.lastVarint(1), 1)
        try assertKept(sent, from: raw, except: [1])
    }

    func testBluetoothPINKeepsBluetoothOn() throws {
        var w = Meshtastic.Writer(); w.varint(field: 1, 1); w.varint(field: 2, 0); w.varint(field: 9, 7)
        var f = Meshtastic.Writer(); f.bytes(field: 7, w.data)
        var from = Meshtastic.Writer(); from.bytes(field: 5, f.data)
        guard case .bluetoothConfig(let raw) = Meshtastic.parse(from.data) else { return XCTFail() }
        XCTAssertFalse(Meshtastic.usesFixedPIN(currentBluetooth: raw))
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.setBluetoothPIN(482_913, currentBluetooth: raw)), section: 7)
        XCTAssertEqual(sent.lastVarint(1), 1, "Bluetooth stays on")
        XCTAssertEqual(sent.lastVarint(2), 1, "FIXED_PIN")
        XCTAssertEqual(sent.lastVarint(3), 482_913)
        try assertKept(sent, from: raw, except: [2, 3])
        XCTAssertNil(Meshtastic.setBluetoothPIN(12_345, currentBluetooth: raw), "leading zero")
        XCTAssertNil(Meshtastic.setBluetoothPIN(1_000_000, currentBluetooth: raw))
    }

    func testLocationOnAndChannelPrecision() throws {
        var position = Meshtastic.Writer(); position.varint(field: 1, 900); position.varint(field: 2, 1); position.varint(field: 10, 100)
        let raw = position.data
        let sent = try sentConfig(try XCTUnwrap(Meshtastic.locationOn(intervalSecs: 1800, currentPosition: raw)), section: 2)
        XCTAssertEqual(sent.lastVarint(13), Meshtastic.GPSMode.enabled)
        XCTAssertEqual(sent.lastVarint(1), 1800)
        try assertKept(sent, from: raw, except: [1, 13])
        XCTAssertNil(Meshtastic.locationOn(intervalSecs: 10, currentPosition: raw))

        var module = Meshtastic.Writer(); module.varint(field: 1, 0); module.varint(field: 2, 1)
        var settings = Meshtastic.Writer(); settings.bytes(field: 2, Data([1])); settings.bytes(field: 3, Data("Mesh".utf8)); settings.bytes(field: 7, module.data)
        var channel = Meshtastic.Writer(); channel.varint(field: 1, 0); channel.bytes(field: 2, settings.data); channel.varint(field: 3, 1)
        let admin = try XCTUnwrap(Meshtastic.channel(positionPrecision: 13, currentChannel: channel.data))
        let ch = try XCTUnwrap(try self.admin(Meshtastic.adminPacket(admin, to: 0xA1, id: 7)).bytes(33).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(ch.lastVarint(3), 1, "role kept")
        let st = try XCTUnwrap(ch.lastBytes(2).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(st.lastBytes(2), Data([1]), "key kept")
        XCTAssertEqual(st.string(3), "Mesh", "name kept")
        let mod = try XCTUnwrap(st.lastBytes(7).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(mod.lastVarint(1), 13)
        XCTAssertEqual(mod.lastVarint(2), 1, "is_muted kept")
        XCTAssertTrue(Meshtastic.isValidPrecision(32))
        XCTAssertFalse(Meshtastic.isValidPrecision(9))
    }

    func testOwnerNamesKeepTheRestOfTheUser() throws {
        var user = Meshtastic.Writer(); user.bytes(field: 1, Data("!12345678".utf8)); user.bytes(field: 2, Data("Old".utf8))
        user.bytes(field: 3, Data("OL".utf8)); user.varint(field: 5, 33); user.bytes(field: 8, Data(repeating: 7, count: 32))
        var node = Meshtastic.Writer(); node.varint(field: 1, 0x1234_5678); node.bytes(field: 2, user.data)
        var from = Meshtastic.Writer(); from.bytes(field: 4, node.data)
        let raw = try XCTUnwrap(Meshtastic.user(fromNodeInfo: from.data))
        let admin = try XCTUnwrap(Meshtastic.setOwner(longName: " Base camp ", shortName: "BC1", currentUser: raw))
        let sent = try XCTUnwrap(try self.admin(Meshtastic.adminPacket(admin, to: 0xA1, id: 7)).bytes(32).flatMap(Meshtastic.Reader.fields))
        XCTAssertEqual(sent.string(2), "Base camp")
        XCTAssertEqual(sent.string(3), "BC1")
        try assertKept(sent, from: raw, except: [2, 3])
        XCTAssertNil(sent.lastVarint(6), "is_licensed not turned on")
        XCTAssertNil(Meshtastic.setOwner(longName: "A", shortName: "TOOLONG", currentUser: raw))
        XCTAssertNil(Meshtastic.setOwner(longName: String(repeating: "x", count: 25), shortName: "X", currentUser: raw))
        XCTAssertNil(Meshtastic.setOwner(longName: "", shortName: "X", currentUser: raw))
    }
}
