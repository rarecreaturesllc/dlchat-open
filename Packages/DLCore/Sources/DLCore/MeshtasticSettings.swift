import Foundation

/// Radio settings DLChat can change on the person's own radio, each written like `setRegion`: the radio's
/// current section is sent back with only the named fields replaced, so settings DLChat does not know survive.
/// Field numbers and enum values are from meshtastic/protobufs config.proto, mesh.proto and admin.proto
/// (checked 2026-11-12). The model sends each between `beginEdit` and `commitEdit`.
extension Meshtastic {
    /// LoRaConfig fields DLChat never writes: region (7), frequency_offset (6), channel_num (11, the frequency
    /// slot), override_duty_cycle (12) and override_frequency (14). Region is only ever set by `setRegion`.
    public static let forbiddenLoRaFields: Set<Int> = [6, 7, 11, 12, 14]

    /// Config oneof field numbers.
    enum Section: Int { case device = 1, position = 2, power = 3, lora = 6, bluetooth = 7 }

    /// AdminMessage { set_config: Config { section } } with only `changes` (field: varint) replaced.
    static func setConfig(_ section: Section, current raw: Data, _ changes: KeyValuePairs<Int, UInt64>) -> Data {
        assert(section != .lora || changes.allSatisfy { !forbiddenLoRaFields.contains($0.key) })
        var s = Writer(keeping: raw, without: Set(changes.map(\.key)))
        for (field, value) in changes { s.varint(field: field, value) }
        var config = Writer(); config.bytes(field: section.rawValue, s.data)
        var admin = Writer(); admin.bytes(field: 34, config.data)
        return admin.data
    }

    // MARK: LoRa

    /// The transmit power the radio is set to (LoRaConfig.tx_power, field 10, int32 dBm). 0 = the region's legal maximum.
    public static func txPower(currentLoRa raw: Data?) -> Int {
        Int(Int32(truncatingIfNeeded: raw.flatMap(Reader.fields)?.lastVarint(10) ?? 0))
    }

    /// LoRaConfig.tx_power: 0 = the highest power legal in the region (the firmware default, not low power),
    /// or 1...30 dBm. The firmware still caps it at the region's and the hardware's limit. nil when out of range.
    public static func setTxPower(_ dBm: Int, currentLoRa raw: Data) -> Data? {
        guard dBm == 0 || (1...30).contains(dBm) else { return nil }
        return setConfig(.lora, current: raw, [10: UInt64(dBm)])
    }

    /// LoRaConfig.hop_limit (field 8), 1...7. nil when out of range.
    public static func setHopLimit(_ hops: Int, currentLoRa raw: Data) -> Data? {
        guard (1...7).contains(hops) else { return nil }
        return setConfig(.lora, current: raw, [8: UInt64(hops)])
    }

    /// LoRaConfig.ModemPreset values DLChat offers: those not deprecated that every region and firmware
    /// since 2.5 knows. LONG_SLOW (1) and VERY_LONG_SLOW (2) are deprecated; LITE/NARROW/TINY (10...15) and
    /// MEDIUM_TURBO (16) are newer and region-limited, left to the Meshtastic app.
    public static let modemPresets: [(code: UInt64, name: String)] = [
        (0, "Long Range - Fast"), (7, "Long Range - Moderate"), (9, "Long Range - Turbo"),
        (3, "Medium Range - Slow"), (4, "Medium Range - Fast"),
        (5, "Short Range - Slow"), (6, "Short Range - Fast"), (8, "Short Range - Turbo"),
    ]

    /// The preset the radio uses, or nil when it uses manual bandwidth/spread factor (use_preset false).
    public static func modemPreset(currentLoRa raw: Data?) -> UInt64? {
        guard let lora = raw.flatMap(Reader.fields), (lora.lastVarint(1) ?? 0) != 0 else { return nil }
        return lora.lastVarint(2) ?? 0
    }

    /// LoRaConfig use_preset (field 1) = true and modem_preset (field 2). Region, frequency slot and duty cycle
    /// are kept as they are; a preset the region does not allow is replaced by the firmware with its default.
    public static func setModemPreset(_ preset: UInt64, currentLoRa raw: Data) -> Data? {
        guard modemPresets.contains(where: { $0.code == preset }) else { return nil }
        return setConfig(.lora, current: raw, [1: 1, 2: preset])
    }

    /// LoRaConfig.config_ok_to_mqtt (field 105) and ignore_mqtt (field 104), both default false.
    public static func mqtt(currentLoRa raw: Data?) -> (okToMQTT: Bool, ignoreMQTT: Bool) {
        let lora = raw.flatMap(Reader.fields) ?? []
        return ((lora.lastVarint(105) ?? 0) != 0, (lora.lastVarint(104) ?? 0) != 0)
    }

    /// `okToMQTT`: sets the ok_to_mqtt bit on this radio's packets, a polite request (not encryption) that official
    /// firmware gateways honour, and only on channels with the default or event key. `ignoreMQTT`: drop packets that
    /// passed through MQTT on the way here.
    public static func setMQTT(okToMQTT: Bool, ignoreMQTT: Bool, currentLoRa raw: Data) -> Data {
        setConfig(.lora, current: raw, [105: okToMQTT ? 1 : 0, 104: ignoreMQTT ? 1 : 0])
    }

    // MARK: Device

    /// Config.DeviceConfig.Role values DLChat offers.
    public enum Role { public static let client: UInt64 = 0, clientMute: UInt64 = 1, tracker: UInt64 = 5 }
    /// Config.DeviceConfig.RebroadcastMode values DLChat offers. ALL_SKIP_DECODING (1) is for the deprecated
    /// Repeater role; NONE only for Sensor, Tracker and TAK Tracker.
    public enum Rebroadcast {
        public static let all: UInt64 = 0, localOnly: UInt64 = 2, knownOnly: UInt64 = 3, none: UInt64 = 4, corePortnumsOnly: UInt64 = 5
    }

    public static func role(currentDevice raw: Data?) -> UInt64 { raw.flatMap(Reader.fields)?.lastVarint(1) ?? Role.client }
    public static func rebroadcastMode(currentDevice raw: Data?) -> UInt64 { raw.flatMap(Reader.fields)?.lastVarint(6) ?? Rebroadcast.all }

    /// DeviceConfig.role (field 1): Client, Client Mute or Tracker. Leaving Tracker while relaying is NONE also
    /// sets rebroadcast_mode (field 6) back to ALL, since NONE is not allowed for the other roles.
    public static func setRole(_ role: UInt64, currentDevice raw: Data) -> Data? {
        guard [Role.client, Role.clientMute, Role.tracker].contains(role) else { return nil }
        if role != Role.tracker, rebroadcastMode(currentDevice: raw) == Rebroadcast.none {
            return setConfig(.device, current: raw, [1: role, 6: Rebroadcast.all])
        }
        return setConfig(.device, current: raw, [1: role])
    }

    /// DeviceConfig.rebroadcast_mode (field 6). NONE only while the role is Tracker. nil when not allowed.
    public static func setRebroadcastMode(_ mode: UInt64, currentDevice raw: Data) -> Data? {
        let allowed = [Rebroadcast.all, Rebroadcast.localOnly, Rebroadcast.knownOnly, Rebroadcast.corePortnumsOnly]
        guard allowed.contains(mode) || (mode == Rebroadcast.none && role(currentDevice: raw) == Role.tracker) else { return nil }
        return setConfig(.device, current: raw, [6: mode])
    }

    // MARK: Power, Bluetooth

    public static func powerSaving(currentPower raw: Data?) -> Bool { (raw.flatMap(Reader.fields)?.lastVarint(1) ?? 0) != 0 }

    /// PowerConfig.is_power_saving (field 1). On nRF52 radios (T-Echo) it only acts in the Tracker and Sensor
    /// roles, where it also sleeps Bluetooth and LoRa between position broadcasts.
    public static func setPowerSaving(_ on: Bool, currentPower raw: Data) -> Data {
        setConfig(.power, current: raw, [1: on ? 1 : 0])
    }

    /// BluetoothConfig.mode (field 2) == FIXED_PIN (1).
    public static func usesFixedPIN(currentBluetooth raw: Data?) -> Bool { raw.flatMap(Reader.fields)?.lastVarint(2) == 1 }

    /// BluetoothConfig mode = FIXED_PIN (field 2 = 1) and fixed_pin (field 3), keeping `enabled` (field 1): the radio
    /// replaces its whole Bluetooth section with what is sent. 100000...999999 only: nRF52 firmware turns the PIN
    /// into text without leading zeros, so a PIN starting with 0 could never be entered.
    public static func setBluetoothPIN(_ pin: UInt32, currentBluetooth raw: Data) -> Data? {
        guard (100_000...999_999).contains(pin) else { return nil }
        return setConfig(.bluetooth, current: raw, [2: 1, 3: UInt64(pin)])
    }

    // MARK: Position

    /// Position broadcast interval DLChat allows (PositionConfig.position_broadcast_secs), in seconds.
    public static let positionIntervals: ClosedRange<UInt32> = 60...86_400
    /// Channel position_precision values DLChat allows besides 0: 10 (about 23 km) to 19 (about 45 m), or 32 (exact).
    /// The firmware caps a channel with a publicly known key (the default LongFast key) at 15 (about 700 m).
    public static func isValidPrecision(_ bits: UInt32) -> Bool { (10...19).contains(bits) || bits == 32 }

    /// PositionConfig gps_mode (13) = ENABLED and position_broadcast_secs (1). Fixed position and smart broadcast kept.
    public static func locationOn(intervalSecs: UInt32, currentPosition raw: Data) -> Data? {
        guard positionIntervals.contains(intervalSecs) else { return nil }
        return setConfig(.position, current: raw, [13: GPSMode.enabled, 1: UInt64(intervalSecs)])
    }

    // MARK: Owner

    /// The User in a FromRadio node_info (field 4 { user: 2 }), raw, to send back with the names changed.
    public static func user(fromNodeInfo data: Data) -> Data? {
        Reader.fields(data)?.bytes(4).flatMap(Reader.fields)?.bytes(2)
    }

    /// The longest names Meshtastic keeps: long_name 24 bytes of UTF-8 (devices cut longer ones, mesh.proto),
    /// short_name 4 bytes (mesh.options max_size 5 with the terminator).
    public static let maxLongName = 24, maxShortName = 4

    /// AdminMessage { set_owner: User } (field 32): the radio's own User with long_name (2) and short_name (3)
    /// replaced. is_licensed (6) is kept as it is: the firmware copies it every time, and turning it on would strip
    /// channel keys. nil for an empty or too long name.
    public static func setOwner(longName: String, shortName: String, currentUser raw: Data) -> Data? {
        let long = longName.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !long.isEmpty, !short.isEmpty, long.utf8.count <= maxLongName, short.utf8.count <= maxShortName else { return nil }
        var user = Writer(keeping: raw, without: [2, 3])
        user.bytes(field: 2, Data(long.utf8))
        user.bytes(field: 3, Data(short.utf8))
        var admin = Writer(); admin.bytes(field: 32, user.data)
        return admin.data
    }
}
