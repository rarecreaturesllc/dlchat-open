import Foundation

/// The Meshtastic phone API over Bluetooth, only as far as DLChat needs it: ask the radio for its
/// state, send a sealed DLChat message as a private-app broadcast, and read what arrives. Written for
/// DLChat from the protocol's public description (message and field numbers, Bluetooth UUIDs); it
/// contains no Meshtastic code. Protobuf encoding by hand: varints, fixed32 and length-delimited fields.
public enum Meshtastic {
    /// Meshtastic sets aside port numbers from 256 for private applications.
    public static let privateAppPort = 256
    public static let broadcast: UInt32 = 0xFFFF_FFFF
    /// The most app data one Meshtastic packet carries.
    public static let maxPayload = 233
    public static let defaultHops: UInt32 = 3

    /// ToRadio { want_config_id }: the radio answers with its state, then config_complete_id = id.
    public static func wantConfig(id: UInt32) -> Data {
        var w = Writer()
        w.varint(field: 3, UInt64(id))
        return w.data
    }

    /// ToRadio { disconnect: true }: tells the radio this app is letting go, so it drops the session at once
    /// and is free for another app, instead of waiting for Bluetooth to time out.
    public static let disconnect: Data = {
        var w = Writer()
        w.varint(field: 4, 1)
        return w.data
    }()

    /// ToRadio { packet: MeshPacket { to: broadcast, channel, decoded: Data { portnum, payload }, id, hop_limit } }
    public static func broadcastPacket(payload: Data, id: UInt32, channel: UInt32 = 0, hops: UInt32 = defaultHops) throws -> Data {
        guard !payload.isEmpty, payload.count <= maxPayload else { throw MeshtasticError.payloadSize(payload.count) }
        var inner = Writer()
        inner.varint(field: 1, UInt64(privateAppPort))
        inner.bytes(field: 2, payload)
        var packet = Writer()
        packet.fixed32(field: 2, broadcast)
        if channel != 0 { packet.varint(field: 3, UInt64(channel)) }
        packet.bytes(field: 4, inner.data)
        packet.fixed32(field: 6, id)
        packet.varint(field: 9, UInt64(hops))
        var toRadio = Writer()
        toRadio.bytes(field: 1, packet.data)
        return toRadio.data
    }

    /// What one FromRadio read holds, as far as DLChat cares.
    public enum FromRadio: Equatable {
        /// A packet the radio could open (its channel key), with the app port and data.
        case packet(from: UInt32, port: Int, payload: Data)
        case myInfo(nodeNum: UInt32)
        case nodeInfo(num: UInt32, longName: String, shortName: String, isLicensed: Bool)
        case configComplete(id: UInt32)
        case rebooted
        /// Config.lora, raw (to send back with one field changed) and its region (0 = unset).
        case loraConfig(raw: Data, region: UInt64)
        /// Config.position, raw. `sharesLocation` is false only when GPS is off and no fixed position is set.
        case positionConfig(raw: Data, sharesLocation: Bool)
        /// A channel, raw. Only the primary (index 0) carries DLChat; `precision` 0 means it never shares a position.
        case channel(raw: Data, index: UInt64, precision: UInt64)
        /// Config.device, Config.power and Config.bluetooth, raw, to send back with fields changed.
        case deviceConfig(raw: Data)
        case powerConfig(raw: Data)
        case bluetoothConfig(raw: Data)
        case other
    }

    /// Parses a FromRadio message. nil only for malformed bytes.
    public static func parse(_ data: Data) -> FromRadio? {
        guard let fields = Reader.fields(data) else { return nil }
        for field in fields {
            switch (field.number, field.value) {
            case (2, .bytes(let packet)):
                guard let p = Reader.fields(packet) else { return nil }
                let from = p.fixed32(1) ?? 0
                guard let decoded = p.bytes(4), let d = Reader.fields(decoded) else { return .other }  // encrypted for a channel we lack
                return .packet(from: from, port: Int(clamping: d.varint(1) ?? 0), payload: d.bytes(2) ?? Data())
            case (3, .bytes(let info)):
                guard let m = Reader.fields(info) else { return nil }
                return .myInfo(nodeNum: UInt32(truncatingIfNeeded: m.varint(1) ?? 0))
            case (4, .bytes(let info)):
                guard let n = Reader.fields(info) else { return nil }
                let user = n.bytes(2).flatMap(Reader.fields) ?? []
                return .nodeInfo(num: UInt32(truncatingIfNeeded: n.varint(1) ?? 0),
                                 longName: user.string(2) ?? "", shortName: user.string(3) ?? "",
                                 isLicensed: (user.varint(6) ?? 0) != 0)
            case (5, .bytes(let config)):
                guard let c = Reader.fields(config) else { return nil }
                if let lora = c.lastBytes(6), let l = Reader.fields(lora) {
                    return .loraConfig(raw: lora, region: l.lastVarint(7) ?? 0)
                }
                if let position = c.lastBytes(2), let pf = Reader.fields(position) {
                    let gpsOn = (pf.lastVarint(13) ?? 0) == GPSMode.enabled
                    let fixed = (pf.lastVarint(3) ?? 0) != 0
                    return .positionConfig(raw: position, sharesLocation: gpsOn || fixed)
                }
                if let device = c.lastBytes(1) { return .deviceConfig(raw: device) }
                if let power = c.lastBytes(3) { return .powerConfig(raw: power) }
                if let bluetooth = c.lastBytes(7) { return .bluetoothConfig(raw: bluetooth) }
                return .other
            case (10, .bytes(let channel)):
                guard let ch = Reader.fields(channel) else { return nil }
                let module = ch.lastBytes(2).flatMap(Reader.fields)?.lastBytes(7).flatMap(Reader.fields)
                return .channel(raw: channel, index: ch.lastVarint(1) ?? 0, precision: module?.lastVarint(1) ?? 0)
            case (7, .varint(let id)):
                return .configComplete(id: UInt32(truncatingIfNeeded: id))
            case (8, .varint):
                return .rebooted
            default:
                continue
            }
        }
        return .other
    }

    // MARK: Radio settings (AdminMessage)

    /// Config.PositionConfig.GpsMode.
    public enum GPSMode { public static let disabled: UInt64 = 0, enabled: UInt64 = 1, notPresent: UInt64 = 2 }

    /// LoRa regions (Config.LoRaConfig.RegionCode) DLChat can pick from the phone's country. Others are
    /// left to the Meshtastic app: a wrong region is illegal to transmit on, so DLChat never guesses.
    public static func region(forCountry country: String) -> (code: UInt64, name: String)? {
        let eu: Set<String> = ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
                               "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "CH", "NO", "IS"]
        switch country.uppercased() {
        case "US", "CA": return (1, "United States and Canada (915 MHz)")
        case "AU", "NZ": return (6, "Australia and New Zealand (915 MHz)")
        case "JP": return (5, "Japan (920 MHz)")
        case "KR": return (7, "Korea (920 MHz)")
        case "TW": return (8, "Taiwan (920 MHz)")
        case "IN": return (10, "India (865 MHz)")
        case let c where eu.contains(c): return (3, "Europe (868 MHz)")
        default: return nil
        }
    }

    /// The hop limit the radio is set to (Config.lora.hop_limit), which Meshtastic apps send every packet with.
    /// Unset (0) or out of range means the firmware default.
    public static func hopLimit(currentLoRa raw: Data?) -> UInt32 {
        guard let hops = raw.flatMap(Reader.fields)?.lastVarint(8), (1...7).contains(hops) else { return defaultHops }
        return UInt32(hops)
    }

    /// AdminMessage { set_config: Config { lora } }: the radio's own LoRa settings with only the region changed.
    public static func setRegion(_ region: UInt64, currentLoRa raw: Data) -> Data {
        var lora = Writer(keeping: raw, without: [7])
        lora.varint(field: 7, region)
        var config = Writer(); config.bytes(field: 6, lora.data)
        var admin = Writer(); admin.bytes(field: 34, config.data)
        return admin.data
    }

    /// AdminMessage { set_config: Config { position } }: GPS off, no fixed position, no smart broadcasts.
    /// The zeros are written out on purpose so they replace whatever the radio had.
    public static func locationOff(currentPosition raw: Data) -> Data {
        var position = Writer(keeping: raw, without: [2, 3, 13])
        position.varint(field: 2, 0)
        position.varint(field: 3, 0)
        position.varint(field: 13, GPSMode.disabled)
        var config = Writer(); config.bytes(field: 2, position.data)
        var admin = Writer(); admin.bytes(field: 34, config.data)
        return admin.data
    }

    /// AdminMessage { set_channel }: the channel unchanged except module_settings.position_precision = 0,
    /// which stops the radio sharing any position on it. Keeps the channel's key, name and role.
    public static func channelWithoutPosition(currentChannel raw: Data) -> Data? {
        channel(positionPrecision: 0, currentChannel: raw)
    }

    /// AdminMessage { set_channel }: the channel unchanged except module_settings.position_precision
    /// (ModuleSettings field 1: bits of latitude/longitude kept, 0 = none). Key, name and role are kept.
    public static func channel(positionPrecision: UInt32, currentChannel raw: Data) -> Data? {
        guard let ch = Reader.fields(raw), let settingsRaw = ch.lastBytes(2), let st = Reader.fields(settingsRaw) else { return nil }
        let module = st.lastBytes(7)
        var moduleOut = Writer(keeping: module ?? Data(), without: [1])
        moduleOut.varint(field: 1, UInt64(positionPrecision))
        var settings = Writer(keeping: settingsRaw, without: [7])
        settings.bytes(field: 7, moduleOut.data)
        var channel = Writer(keeping: raw, without: [2])
        channel.bytes(field: 2, settings.data)
        var admin = Writer(); admin.bytes(field: 33, channel.data)
        return admin.data
    }

    /// AdminMessage begin_edit_settings / commit_edit_settings: changes in between are saved together,
    /// with at most one restart.
    public static let beginEdit: Data = { var w = Writer(); w.varint(field: 64, 1); return w.data }()
    public static let commitEdit: Data = { var w = Writer(); w.varint(field: 65, 1); return w.data }()

    /// ToRadio { packet: MeshPacket { to: node, decoded: Data { portnum: ADMIN_APP, payload }, id } }:
    /// a settings change for the radio this phone is connected to.
    public static func adminPacket(_ admin: Data, to node: UInt32, id: UInt32) -> Data {
        var inner = Writer()
        inner.varint(field: 1, adminPort)
        inner.bytes(field: 2, admin)
        var packet = Writer()
        packet.fixed32(field: 2, node)
        packet.bytes(field: 4, inner.data)
        packet.fixed32(field: 6, id)
        var toRadio = Writer()
        toRadio.bytes(field: 1, packet.data)
        return toRadio.data
    }

    static let adminPort: UInt64 = 6

    // MARK: Protobuf

    public struct Writer {
        public private(set) var data = Data()
        public init() {}

        /// Starts from an existing message, dropping the given fields so they can be written fresh.
        /// Unknown fields pass through untouched, so settings DLChat does not know survive.
        public init(keeping raw: Data, without dropped: Set<Int>) {
            for f in Reader.fields(raw) ?? [] where !dropped.contains(f.number) { field(f) }
        }

        public mutating func field(_ f: Field) {
            switch f.value {
            case .varint(let v): varint(field: f.number, v)
            case .fixed32(let v): fixed32(field: f.number, v)
            case .bytes(let v): bytes(field: f.number, v)
            case .fixed64(let v):
                raw(UInt64(f.number << 3 | 1))
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
        }

        public mutating func varint(field: Int, _ value: UInt64) {
            raw(UInt64(field << 3 | 0)); raw(value)
        }
        public mutating func fixed32(field: Int, _ value: UInt32) {
            raw(UInt64(field << 3 | 5))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        public mutating func bytes(field: Int, _ value: Data) {
            raw(UInt64(field << 3 | 2)); raw(UInt64(value.count)); data.append(value)
        }
        private mutating func raw(_ value: UInt64) {
            var v = value
            while v >= 0x80 { data.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
            data.append(UInt8(v))
        }
    }

    public enum Value: Equatable { case varint(UInt64), fixed64(UInt64), bytes(Data), fixed32(UInt32) }
    public struct Field: Equatable {
        public let number: Int, value: Value
        public init(number: Int, value: Value) { self.number = number; self.value = value }
    }

    public enum Reader {
        /// Every top-level field, or nil if the bytes are not a well-formed protobuf message.
        public static func fields(_ data: Data) -> [Field]? {
            let b = [UInt8](data)
            var i = 0, out: [Field] = []
            func varint() -> UInt64? {
                var result: UInt64 = 0, shift: UInt64 = 0
                while i < b.count, shift < 64 {
                    let byte = b[i]; i += 1
                    result |= UInt64(byte & 0x7F) << shift
                    if byte & 0x80 == 0 { return result }
                    shift += 7
                }
                return nil
            }
            while i < b.count {
                // Protobuf field numbers stop at 2^29 - 1; a larger one is not a real message.
                guard let key = varint(), key >> 3 > 0, key >> 3 < 1 << 29 else { return nil }
                let number = Int(key >> 3)
                switch key & 7 {
                case 0:
                    guard let v = varint() else { return nil }
                    out.append(Field(number: number, value: .varint(v)))
                case 1:
                    guard i + 8 <= b.count else { return nil }
                    let v = (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[i + $1]) << (8 * UInt64($1)) }
                    i += 8; out.append(Field(number: number, value: .fixed64(v)))
                case 2:
                    guard let len = varint(), len <= UInt64(b.count - i) else { return nil }
                    out.append(Field(number: number, value: .bytes(Data(b[i..<(i + Int(len))])))); i += Int(len)
                case 5:
                    guard i + 4 <= b.count else { return nil }
                    let v = (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[i + $1]) << (8 * UInt32($1)) }
                    i += 4; out.append(Field(number: number, value: .fixed32(v)))
                default:
                    return nil  // groups (3, 4) are not used by Meshtastic
                }
            }
            return out
        }
    }
}

public enum MeshtasticError: Error, Equatable { case payloadSize(Int) }

extension Array where Element == Meshtastic.Field {
    public func varint(_ n: Int) -> UInt64? { for f in self where f.number == n { if case .varint(let v) = f.value { return v } }; return nil }
    public func fixed32(_ n: Int) -> UInt32? { for f in self where f.number == n { if case .fixed32(let v) = f.value { return v } }; return nil }
    public func bytes(_ n: Int) -> Data? { for f in self where f.number == n { if case .bytes(let v) = f.value { return v } }; return nil }
    public func string(_ n: Int) -> String? { bytes(n).map { String(decoding: $0, as: UTF8.self) } }
    /// Protobuf keeps the last value when a field repeats; settings are read that way.
    public func lastVarint(_ n: Int) -> UInt64? { for f in reversed() where f.number == n { if case .varint(let v) = f.value { return v } }; return nil }
    public func lastBytes(_ n: Int) -> Data? { for f in reversed() where f.number == n { if case .bytes(let v) = f.value { return v } }; return nil }
}
