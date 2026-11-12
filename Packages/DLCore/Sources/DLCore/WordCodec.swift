import Foundation

public enum WordCodecError: Error, Equatable {
    case unknownWord(index: Int)
    case notWholeWords
}

/// Frames to spoken words and back: 10 bits per word from the 1024-word list.
public enum WordCodec {
    /// Fewest body words: P after the tag is at least this many words long.
    public static let minimumBodyWords = 4

    /// Random bits to append to `body` so the sealed frame (`tagBits` of tag,
    /// the 28-bit header, the body) is a whole number of words and has at
    /// least `minimumBodyWords` words after the tag. The padding is inside the
    /// authenticated data, so it must be added before sealing.
    public static func pad(
        _ body: Bits, tagBits: Int,
        using generator: inout some RandomNumberGenerator
    ) -> Bits {
        let wordBits = WordList.bitsPerWord
        var total = Frame.headerBits + body.count
        total = max(total, minimumBodyWords * wordBits)
        let padBits = (wordBits - (tagBits + total) % wordBits) % wordBits + (total - Frame.headerBits - body.count)
        var out = body
        var remaining = padBits
        while remaining > 0 {
            let width = min(remaining, 32)
            out.append(UInt64.random(in: 0..<(1 << UInt64(width)), using: &generator), width: width)
            remaining -= width
        }
        return out
    }

    public static func pad(_ body: Bits, tagBits: Int) -> Bits {
        var generator = SystemRandomNumberGenerator()
        return pad(body, tagBits: tagBits, using: &generator)
    }

    public static func encode(_ frame: Frame) throws -> [String] {
        let bits = frame.bits
        guard bits.count % WordList.bitsPerWord == 0 else { throw WordCodecError.notWholeWords }
        return stride(from: 0, to: bits.count, by: WordList.bitsPerWord).map {
            WordList.word(at: Int(bits.value(at: $0, width: WordList.bitsPerWord)))
        }
    }

    public static func decode(_ words: [String]) throws -> Frame {
        var bits = Bits()
        for (i, word) in words.enumerated() {
            guard let index = WordList.index(of: word) else { throw WordCodecError.unknownWord(index: i) }
            bits.append(UInt64(index), width: WordList.bitsPerWord)
        }
        return Frame(bits: bits)
    }
}
