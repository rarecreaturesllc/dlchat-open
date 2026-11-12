import Foundation

/// Sentence marks (! ? . ,) for Chat messages, carried after the text's END.
///
/// `TextCodec` codes only words and numbers, so marks were dropped. Changing its token table
/// would break every older phone, so the marks ride after END instead, where older versions
/// see only padding and show the words as before. Text without marks codes exactly as before.
///
/// Wire, after END: a 16-bit magic, an 8-bit count, then per mark the index of the word it
/// follows (8 bits) and the mark (2 bits), in order, then a CRC-8 over count and marks.
/// Padding is random, so the magic, the order and the check keep padding from reading as marks.
public enum Punctuation {
    public static let symbols: [Character] = ["!", "?", ".", ","]
    static let magic: UInt64 = 0xD1C7
    static let markBits = 2
    static let maxCount = 255
    static let maxWordIndex = 255

    public struct Mark: Equatable {
        /// Index of the word (as `TextCodec` splits the text) the mark follows.
        public let word: Int
        public let mark: Character
    }

    /// The marks in `text` that end a word: a mark (or a run of marks) after a word and not followed
    /// by a letter or digit, so "3.5" and "e.g" keep their old spacing. Marks before any word are dropped.
    public static func marks(in text: String) -> [Mark] {
        let scalars = Array(text.lowercased().unicodeScalars)
        var result: [Mark] = []
        var pending: [Character] = []
        for (i, scalar) in scalars.enumerated() {
            let ch = Character(scalar)
            guard symbols.contains(ch) else { pending = []; continue }
            pending.append(ch)
            let next = i + 1 < scalars.count ? scalars[i + 1] : nil
            guard next.map(isWordChar) != true else { pending = []; continue }
            guard next.map({ symbols.contains(Character($0)) }) != true else { continue }
            // The words before this mark are the text's first words, so their count places it.
            var prefix = String.UnicodeScalarView()
            prefix.append(contentsOf: scalars[..<i])
            let words = TextCodec.runCount(in: String(prefix))
            if words > 0 { result += pending.map { Mark(word: words - 1, mark: $0) } }
            pending = []
        }
        return result
    }

    /// The trailer for `marks`, or empty when there are none (or the text is too long to place them).
    static func trailer(_ marks: [Mark]) -> Bits {
        let kept = marks.filter { $0.word <= maxWordIndex }.prefix(maxCount)
        guard !kept.isEmpty else { return Bits() }
        var bits = Bits()
        bits.append(magic, width: 16)
        bits.append(UInt64(kept.count), width: 8)
        var entries: [UInt8] = [UInt8(kept.count)]
        for m in kept {
            let code = UInt8(symbols.firstIndex(of: m.mark)!)
            bits.append(UInt64(m.word), width: 8)
            bits.append(UInt64(code), width: markBits)
            entries += [UInt8(m.word), code]
        }
        bits.append(UInt64(check(entries)), width: 8)
        return bits
    }

    /// Text coded as `TextCodec.encode`, with its marks after END. Same bits as before when it has none.
    public static func encode(_ text: String) throws -> Bits {
        var bits = try TextCodec.encode(text)
        bits.append(trailer(marks(in: text)))
        return bits
    }

    /// The marks in an opened body after END (at bit `end`), checked against `wordCount`. Empty if
    /// none were sent, or the bits there are padding.
    public static func read(_ body: Bits, from end: Int, wordCount: Int) -> [Mark] {
        var at = end
        func take(_ width: Int) -> UInt64? {
            guard at + width <= body.count else { return nil }
            defer { at += width }
            return body.value(at: at, width: width)
        }
        guard take(16) == magic, let count = take(8), count > 0 else { return [] }
        var result: [Mark] = []
        var entries: [UInt8] = [UInt8(count)]
        for _ in 0..<count {
            guard let word = take(8), let code = take(markBits) else { return [] }
            let index = Int(word)
            guard index < wordCount, index >= (result.last?.word ?? 0) else { return [] }
            result.append(Mark(word: index, mark: symbols[Int(code)]))
            entries += [UInt8(word), UInt8(code)]
        }
        guard take(8) == UInt64(check(entries)) else { return [] }
        return result
    }

    /// Bits a trailer of `count` marks takes after END (magic, count, marks, check), so what follows it is found.
    public static func trailerBits(count: Int) -> Int { 16 + 8 + count * (8 + markBits) + 8 }

    /// `words` joined by spaces, each followed by its marks.
    public static func apply(_ marks: [Mark], to words: [String]) -> String {
        var out = words
        for m in marks where m.word < out.count { out[m.word].append(m.mark) }
        return out.joined(separator: " ")
    }

    /// CRC-8 (polynomial 0x07), so any one flipped bit in the marks is caught.
    private static func check(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc
    }

    private static func isWordChar(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 97 && s.value <= 122) || (s.value >= 48 && s.value <= 57)
    }
}
