import Foundation

/// What a nearby phone sends: one hop count byte, then the sealed frame bytes. Nothing else, so a
/// relay phone learns nothing about the group, the room, the sender or the text.
public enum NearbyWire {
    public static let maxBytes = 1024
    /// Hops a message made on this phone may take.
    public static let startTTL: UInt8 = 4

    public static func wire(frame: Data, ttl: UInt8) -> Data {
        Data([ttl]) + frame
    }

    /// The hop count and frame bytes, or nil when the bytes are too large or cannot be a frame.
    /// A hop count above `startTTL` is lowered to it, so a nearby phone cannot make a frame travel further.
    public static func parse(_ data: Data) -> (ttl: UInt8, frame: Data)? {
        guard data.count > 1, data.count <= maxBytes else { return nil }
        let frame = Data(data.dropFirst())
        guard Modem.frame(from: frame) != nil else { return nil }
        return (min(data[data.startIndex], startTTL), frame)
    }
}

extension Composer {
    /// The frame bytes of a sealed message for Nearby and Chat (128-bit tag, as QR and tones).
    /// `replyTo`: the earlier message this answers; `callSign`: the sender's. Both are sealed in after
    /// the text, in that order (see `ReplyTo`, `CallSign`), after any punctuation marks.
    public static func composeNearby(
        text: String, keys: Keys, sentAt: Date = Date(), flags: UInt8 = 0, replyTo: ReplyTo? = nil, callSign: CallSign? = nil
    ) throws -> Data {
        let tagBits = QRTransport.tagBits
        // Encrypted words or sound posted in Chat go as raw frame bits, not spelled out letter by letter.
        // Other text keeps its ! ? . , (see `Punctuation`).
        var coded = try ChatCarry.parse(text).map { try ChatCarry.body($0) } ?? Punctuation.encode(text)
        if let replyTo { coded.append(replyTo.bits) }
        if let callSign { coded.append(callSign.bits) }
        let body = WordCodec.pad(coded, tagBits: tagBits)
        let frame = try Frame.seal(body: body, flags: flags, sentAt: sentAt, keys: keys, tagBits: tagBits)
        return Data(frame.bits.bytes)
    }
}

extension Receiver {
    /// Opens a Nearby wire message. Nil if it is not a frame or no key set authenticates it.
    public static func readNearby(wire: Data, trying keys: [Keys]) -> ReadMessage? {
        guard let parsed = NearbyWire.parse(wire) else { return nil }
        return readTone(payload: parsed.frame, trying: keys)
    }
}
