import Foundation

/// A sealed message carried inside a Chat message: Send > Encrypt Words or Encrypt Sound, posted in
/// Chat, where the other person copies the words or taps the sound into Receive to decrypt them.
///
/// On the phone a carried message is text: its marker, then the carried frame as list words
/// ("dlwords abandon ability …"). On the wire the Chat body is the marker coded as text, END, a
/// count of words (8 bits), then the frame's raw bits, so the words are not spelled out letter by
/// letter. Older versions read only the marker and show it as the message.
public enum ChatCarry {
    public enum Kind: String, CaseIterable {
        /// A voice frame (64-bit tag): Receive > paste the words > Decrypt.
        case words = "dlwords"
        /// A tone frame (128-bit tag): Receive > Decrypt Sound plays it, then opens it.
        case sound = "dlsound"
    }

    public struct Carried: Equatable {
        public let kind: Kind
        public let frame: Frame

        public init(kind: Kind, frame: Frame) {
            self.kind = kind
            self.frame = frame
        }

        /// The frame as list words: what Receive takes for `.words`.
        public var words: [String] {
            stride(from: 0, to: frame.bits.count, by: WordList.bitsPerWord).map {
                WordList.word(at: Int(frame.bits.value(at: $0, width: WordList.bitsPerWord)))
            }
        }

        /// The frame bytes, as a heard tone burst gives them: what Receive takes for `.sound`.
        public var payload: Data { Data(frame.bits.bytes) }

        /// The text stored and shown on the phone.
        public var text: String { ([kind.rawValue] + words).joined(separator: " ") }
    }

    /// Most words one carried frame may have (the count is 8 bits).
    public static let maxWords = 255

    /// The text for a carried frame. Nil if the frame is not whole words or is too long.
    public static func text(_ kind: Kind, frame: Frame) -> String? {
        let bits = frame.bits.count
        guard bits > 0, bits % WordList.bitsPerWord == 0, bits / WordList.bitsPerWord <= maxWords,
              fits(kind, frame) else { return nil }
        return Carried(kind: kind, frame: frame).text
    }

    /// The text for carried words, as Send > Encrypt Words makes them.
    public static func text(words: [String]) -> String? {
        guard let frame = try? WordCodec.decode(words) else { return nil }
        return text(.words, frame: frame)
    }

    /// Reads carried text back: the marker, then only list words, enough for a frame.
    public static func parse(_ text: String) -> Carried? {
        let parts = text.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard let first = parts.first, let kind = Kind(rawValue: first) else { return nil }
        let words = Array(parts.dropFirst())
        guard words.count >= Receiver.minimumWords, words.count <= maxWords,
              let frame = try? WordCodec.decode(words), fits(kind, frame) else { return nil }
        return Carried(kind: kind, frame: frame)
    }

    /// A sound must fit one tone burst, so Receive can play it.
    private static func fits(_ kind: Kind, _ frame: Frame) -> Bool {
        kind == .words || frame.bits.bytes.count <= Modem.maxPayload
    }

    /// The Chat body for carried text: marker, END, word count, frame bits. Padding is added when sealed.
    public static func body(_ carried: Carried) throws -> Bits {
        var bits = try TextCodec.encode(carried.kind.rawValue)
        bits.append(UInt64(carried.frame.bits.count / WordList.bitsPerWord), width: 8)
        bits.append(carried.frame.bits)
        return bits
    }

    /// The carried text, when an opened Chat body read as `marker` holds a carried frame after END
    /// (at bit `end`). Nil for any other message, so it is shown as it was written.
    public static func read(marker: String, body: Bits, from end: Int) -> String? {
        guard let kind = Kind(rawValue: marker), end + 8 <= body.count else { return nil }
        let count = Int(body.value(at: end, width: 8))
        let bits = count * WordList.bitsPerWord
        guard count >= Receiver.minimumWords, end + 8 + bits <= body.count else { return nil }
        let frame = Frame(bits: body.slice(from: end + 8, count: bits))
        guard fits(kind, frame) else { return nil }
        return Carried(kind: kind, frame: frame).text
    }
}
