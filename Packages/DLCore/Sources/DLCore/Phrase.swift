import CryptoKit
import Foundation

public enum PhraseError: Error, Equatable {
    case unsupportedLength(Int)
    case unknownWord(Int)
    case badChecksum
    case randomFailed
}

/// A generated group phrase of 10, 15 or 20 words from the radio list. The
/// last 4 bits are a checksum: the top 4 bits of SHA-256 over the preceding
/// `10 * words - 4` bits, packed MSB first and zero padded to whole bytes.
public struct Phrase: Equatable {
    public static let lengths = [10, 15, 20]
    static let checksumBits = 4

    public let indices: [Int]

    public var words: [String] { indices.map(WordList.word(at:)) }

    /// The words joined by single spaces. This exact text feeds the KDF.
    public var text: String { words.joined(separator: " ") }

    public static func generate(words: Int = 15) throws -> Phrase {
        guard lengths.contains(words) else { throw PhraseError.unsupportedLength(words) }
        var entropy = [UInt8](repeating: 0, count: (words * WordList.bitsPerWord - checksumBits + 7) / 8)
        guard SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy) == errSecSuccess else {
            throw PhraseError.randomFailed
        }
        return try Phrase(entropy: entropy, words: words)
    }

    /// Builds a phrase from known entropy. Used by `generate` and the vectors.
    init(entropy: [UInt8], words: Int) throws {
        guard Phrase.lengths.contains(words) else { throw PhraseError.unsupportedLength(words) }
        let secretBits = words * WordList.bitsPerWord - Phrase.checksumBits
        precondition(entropy.count * 8 >= secretBits, "not enough entropy")
        var bits = Bits(bytes: entropy, count: secretBits)
        bits.append(Phrase.checksum(of: bits), width: Phrase.checksumBits)
        indices = (0..<words).map { Int(bits.value(at: $0 * WordList.bitsPerWord, width: WordList.bitsPerWord)) }
    }

    /// Accepts words separated by any whitespace, in any case.
    public static func parse(_ text: String) throws -> Phrase {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard lengths.contains(parts.count) else { throw PhraseError.unsupportedLength(parts.count) }
        var bits = Bits()
        var indices: [Int] = []
        for (i, part) in parts.enumerated() {
            guard let index = WordList.index(of: part) else { throw PhraseError.unknownWord(i) }
            indices.append(index)
            bits.append(UInt64(index), width: WordList.bitsPerWord)
        }
        let secretBits = bits.count - checksumBits
        let expected = checksum(of: bits.slice(from: 0, count: secretBits))
        guard bits.value(at: secretBits, width: checksumBits) == expected else {
            throw PhraseError.badChecksum
        }
        return Phrase(validIndices: indices)
    }

    private init(validIndices: [Int]) {
        indices = validIndices
    }

    private static func checksum(of secret: Bits) -> UInt64 {
        let digest = Array(SHA256.hash(data: secret.bytes))
        return UInt64(digest[0] >> 4)
    }
}
