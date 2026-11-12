import Foundation

/// Plain Meshtastic text messages (TEXT_MESSAGE_APP), so DLChat can talk with people on the stock
/// Meshtastic app: on a channel (the public one, or any other the radio has) and directly to one radio.
/// These are not sealed with a DLChat phrase. A channel message is readable by everyone with that
/// channel's key (for the default public channel, anyone). A direct message is encrypted by the radio
/// with Meshtastic's own public keys (firmware 2.5+), and DLChat asks it to fail rather than fall back to
/// the channel key. Written from the protocol's public field numbers, like the rest of `Meshtastic`.
extension Meshtastic {
    /// TEXT_MESSAGE_APP: UTF-8 text.
    public static let textPort = 1
    /// ROUTING_APP: acknowledgements and delivery errors for packets sent with want_ack.
    public static let routingPort = 5
    /// What the Meshtastic apps allow in one text message, in UTF-8 bytes.
    public static let maxTextBytes = 200

    /// Every field of a received MeshPacket that Chat uses.
    public struct Packet: Equatable {
        public let from: UInt32
        public let to: UInt32
        /// The channel index it came in on (broadcasts). Direct messages by public key use 0.
        public let channel: UInt32
        public let id: UInt32
        public let port: Int
        public let payload: Data
        /// For an acknowledgement: the id of the packet it answers (Data.request_id).
        public let requestID: UInt32
        /// The radio opened it with Meshtastic's public-key encryption, not a channel key.
        public let pkiEncrypted: Bool
        /// When the radio received it, if the radio knew the time.
        public let received: Date?
        /// Hops it took to reach this radio, when the sender said how many it started with.
        public let hops: Int?

        public var isBroadcast: Bool { to == Meshtastic.broadcast }

        public init(from: UInt32, to: UInt32, channel: UInt32 = 0, id: UInt32 = 0, port: Int, payload: Data,
                    requestID: UInt32 = 0, pkiEncrypted: Bool = false, received: Date? = nil, hops: Int? = nil) {
            self.from = from; self.to = to; self.channel = channel; self.id = id; self.port = port; self.payload = payload
            self.requestID = requestID; self.pkiEncrypted = pkiEncrypted; self.received = received; self.hops = hops
        }
    }

    /// The decoded packet in a FromRadio message, or nil when it is something else or the radio could not open it.
    public static func packet(fromRadio data: Data) -> Packet? {
        guard let fields = Reader.fields(data), let raw = fields.lastBytes(2), let p = Reader.fields(raw),
              let decodedRaw = p.lastBytes(4), let d = Reader.fields(decodedRaw) else { return nil }
        let hopLimit = p.lastVarint(9), hopStart = p.lastVarint(15)
        let hops: Int? = {
            guard let start = hopStart, let limit = hopLimit, start > 0, start >= limit else { return nil }
            return Int(clamping: start - limit)
        }()
        let rx = p.fixed32(7).flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: TimeInterval($0)) }
        return Packet(from: p.fixed32(1) ?? 0, to: p.fixed32(2) ?? 0, channel: UInt32(truncatingIfNeeded: p.lastVarint(3) ?? 0),
                      id: p.fixed32(6) ?? 0, port: Int(clamping: d.lastVarint(1) ?? 0), payload: d.lastBytes(2) ?? Data(),
                      requestID: d.fixed32(6) ?? 0, pkiEncrypted: (p.lastVarint(17) ?? 0) != 0, received: rx, hops: hops)
    }

    /// ToRadio { packet: MeshPacket { to, channel, decoded: Data { portnum: TEXT_MESSAGE_APP, payload }, id, hop_limit, want_ack, pki_encrypted?, public_key? } }.
    /// `to` is `broadcast` for a channel message. Any other `to` is a direct message: it is marked
    /// pki_encrypted, so the radio refuses (PKI_FAILED / PKI_UNKNOWN_PUBKEY) instead of falling back to a
    /// channel key everyone on that channel could open.
    public static func textPacket(_ text: String, to: UInt32, channel: UInt32 = 0, id: UInt32, hops: UInt32 = defaultHops,
                                  publicKey: Data? = nil) throws -> Data {
        let body = Data(text.utf8)
        guard !body.isEmpty, body.count <= maxTextBytes else { throw MeshtasticError.payloadSize(body.count) }
        let direct = to != broadcast
        var inner = Writer()
        inner.varint(field: 1, UInt64(textPort))
        inner.bytes(field: 2, body)
        var packet = Writer()
        packet.fixed32(field: 2, to)
        if !direct, channel != 0 { packet.varint(field: 3, UInt64(channel)) }
        packet.bytes(field: 4, inner.data)
        packet.fixed32(field: 6, id)
        packet.varint(field: 9, UInt64(hops))
        packet.varint(field: 10, 1)  // want_ack: the radio reports delivery or why it failed
        if direct {
            if let publicKey, publicKey.count == 32 { packet.bytes(field: 16, publicKey) }
            packet.varint(field: 17, 1)
        }
        var toRadio = Writer()
        toRadio.bytes(field: 1, packet.data)
        return toRadio.data
    }

    /// Routing { error_reason = 3 } from a ROUTING_APP payload. 0 (NONE) is a successful acknowledgement.
    public static func routingError(_ payload: Data) -> UInt64 {
        Reader.fields(payload)?.lastVarint(3) ?? 0
    }

    /// A plain-words reason for a Routing.Error code, for a message that did not get through.
    public static func routingProblem(_ code: UInt64) -> String {
        switch code {
        case 0: return ""
        case 1: return "no route to that radio"
        case 2, 3, 5, 8: return "no radio answered"
        case 6: return "the radio does not have that channel"
        case 7: return "too long"
        case 9: return "the radio hit its airtime limit; try again in a few minutes"
        case 33: return "not allowed by the radio"
        case 34, 35: return "their radio's key is not known yet. Wait until it announces itself, then try again"
        default: return "the radio could not send it (code \(code))"
        }
    }

    /// Text from a stranger's radio, for display only: valid UTF-8, no control characters but line breaks, capped.
    public static func cleanText(_ payload: Data) -> String {
        let s = String(decoding: payload.prefix(maxPayload), as: UTF8.self)
        let kept = s.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        return String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Channels

    /// One of the radio's channels, as Chat lists it.
    public struct ChannelInfo: Equatable, Identifiable {
        public let index: UInt32
        /// The channel's own name; empty for a primary channel left at its default.
        public let name: String
        /// 1 primary, 2 secondary.
        public let role: UInt64
        /// The key is published (Meshtastic's default key, one of its well-known short keys, or none at all),
        /// so anyone with a Meshtastic radio can read this channel.
        public let keyIsPublic: Bool
        /// This radio forwards the channel's messages to an internet (MQTT) server.
        public let uplink: Bool
        public var id: UInt32 { index }

        public init(index: UInt32, name: String, role: UInt64, keyIsPublic: Bool, uplink: Bool) {
            self.index = index; self.name = MeshMap.clean(name); self.role = role; self.keyIsPublic = keyIsPublic; self.uplink = uplink
        }

        /// The name to show: its own, else the preset name Meshtastic apps use for a default primary ("LongFast").
        public func title(preset: String?) -> String {
            if !name.isEmpty { return name }
            return role == 1 ? (preset ?? "Primary channel") : "Channel \(index)"
        }
    }

    /// Channel { index = 1, settings = 2 { psk = 2, name = 3, uplink_enabled = 5 }, role = 3 }. nil for a disabled slot.
    public static func channelInfo(_ raw: Data) -> ChannelInfo? {
        guard let ch = Reader.fields(raw) else { return nil }
        let role = ch.lastVarint(3) ?? 0
        guard role == 1 || role == 2 else { return nil }
        let settings = ch.lastBytes(2).flatMap(Reader.fields) ?? []
        let psk = settings.lastBytes(2) ?? Data()
        return ChannelInfo(index: UInt32(truncatingIfNeeded: ch.lastVarint(1) ?? 0), name: settings.lastBytes(3).map { String(decoding: $0, as: UTF8.self) } ?? "",
                           role: role, keyIsPublic: psk.count <= 1, uplink: (settings.lastVarint(5) ?? 0) != 0)
    }

    /// The modem preset's name as Meshtastic apps show it for a default primary channel ("LongFast"),
    /// from Config.lora { use_preset = 1, modem_preset = 2 }. nil when the radio uses custom settings or none arrived.
    public static func presetName(currentLoRa raw: Data?) -> String? {
        guard let lora = raw.flatMap(Reader.fields), (lora.lastVarint(1) ?? 0) != 0 else { return nil }
        let names = ["LongFast", "LongSlow", "VLongSlow", "MediumSlow", "MediumFast", "ShortSlow", "ShortFast", "LongMod", "ShortTurbo"]
        let preset = Int(clamping: lora.lastVarint(2) ?? 0)
        return names.indices.contains(preset) ? names[preset] : nil
    }
}
