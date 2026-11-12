import CryptoKit
import Foundation

/// Read receipts (docs/design/read-receipts.md): a phone that turned them on for a group tells the
/// group which messages it has seen in Chat, and only phones that turned them on too take any notice.
///
/// A receipt is a sealed frame like any chat message, under keys of its own (the group master with a
/// room word no one can type), so relays and radios see one more ordinary sealed post, and older
/// versions cannot open it and drop it without showing anything. Inside: a version, the reader's
/// random tag for this group, and short references to the messages read. No text, no names.
public enum ReadReceipt {
    /// The room word receipts are sealed under. A NUL cannot be typed into a room field.
    static let roomWord = "\u{0}read"
    /// Most messages one receipt names: keeps it well under the radio's 233 bytes.
    public static let maxRefs = 15
    static let version: UInt64 = 1
    static let refBits = 40

    public struct Opened: Equatable {
        /// The reader's random tag for this group (changes each time they turn receipts on).
        public let reader: UInt16
        public let refs: [UInt64]
        /// Position in the `trying` list of the keys that opened it.
        public let keysIndex: Int
    }

    /// A 40-bit reference to a message, the same on every phone that opened it (the local group id is
    /// left out: it differs per phone). Nothing outside the group can work it back to a message.
    public static func ref(of message: ReadMessage, room: String) -> UInt64 {
        var data = Data("DLChat/v1/read".utf8)
        data.append(0)
        data.append(Data(Keys.normalizedRoom(room).utf8))
        data.append(0)
        data.append(Data(String(Int(message.sentAt.timeIntervalSince1970)).utf8))
        data.append(0)
        data.append(contentsOf: [message.salt, message.flags])
        data.append(Data(message.text.utf8))
        return SHA256.hash(data: data).prefix(5).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    /// A Nearby wire message (hop byte + frame) saying `reader` has read `refs` (1 to `maxRefs`).
    /// `keys` are the group's receipt keys (`Keys.receiptKeys`).
    public static func wire(reader: UInt16, refs: [UInt64], keys: Keys, sentAt: Date = Date()) throws -> Data {
        guard (1...maxRefs).contains(refs.count) else { throw FrameError.badField }
        var body = Bits()
        body.append(version, width: 4)
        body.append(UInt64(reader), width: 16)
        body.append(UInt64(refs.count), width: 4)
        for ref in refs { body.append(ref & ((1 << UInt64(refBits)) - 1), width: refBits) }
        let frame = try Frame.seal(body: WordCodec.pad(body, tagBits: QRTransport.tagBits), sentAt: sentAt,
                                   keys: keys, tagBits: QRTransport.tagBits)
        return NearbyWire.wire(frame: Data(frame.bits.bytes), ttl: NearbyWire.startTTL)
    }

    /// Opens a receipt. Nil for anything else, including every ordinary message.
    public static func open(wire: Data, trying keys: [Keys]) -> Opened? {
        guard let parsed = NearbyWire.parse(wire), let frame = Modem.frame(from: parsed.frame),
              let opened = Frame.open(frame, tagBits: QRTransport.tagBits, trying: keys) else { return nil }
        let body = opened.body
        guard body.count >= 24, body.value(at: 0, width: 4) == version else { return nil }
        let count = Int(body.value(at: 20, width: 4))
        guard count >= 1, 24 + count * refBits <= body.count else { return nil }
        let refs = (0..<count).map { body.value(at: 24 + $0 * refBits, width: refBits) }
        return Opened(reader: UInt16(body.value(at: 4, width: 16)), refs: refs, keysIndex: opened.keysIndex)
    }
}

extension Keys {
    /// The keys a group's read receipts are sealed under. Ordinary messages never open with them.
    public var receiptKeys: Keys { Keys(master: master, room: ReadReceipt.roomWord) }
}
