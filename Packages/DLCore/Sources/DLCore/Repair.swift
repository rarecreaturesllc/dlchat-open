import Foundation

/// A message recovered by changing one word. The app must show it as repaired
/// and name the word that changed (blueprint section 3, error repair).
public struct Repaired: Equatable {
    public let opened: Opened
    /// Zero-based position of the changed word.
    public let position: Int
    /// What was heard or typed there; nil when the word was missing (`?`) or not on the list.
    public let heard: String?
    /// The word that makes the message authenticate.
    public let replacement: String
    /// True when the position was marked missing, false when a heard word was replaced.
    public let wasMissing: Bool
}

/// Single-word repair. The tag is the checker, so repair adds nothing on air.
/// A successful search spends about 14 bits of the 64-bit forgery margin on
/// voice, and the caller must say so by labelling the result.
public enum Repair {
    /// The marker for a word the listener did not catch.
    public static let missingMarker = "?"

    /// Finds the single word that, once changed, lets the frame authenticate.
    ///
    /// - A word that is `?` or not on the list is a known gap: only that
    ///   position is searched (1024 candidates). More than one gap returns nil.
    /// - Otherwise every position is tried with every other word, about
    ///   `1023 * words.count` candidates.
    /// - Returns nil if nothing authenticates, including when the message is
    ///   already intact (use `Frame.open` first).
    public static func search(words: [String], tagBits: Int, trying keys: [Keys]) -> Repaired? {
        guard !keys.isEmpty, !words.isEmpty else { return nil }
        let wordBits = WordList.bitsPerWord
        let indices: [Int?] = words.map { $0 == missingMarker ? nil : WordList.index(of: $0) }
        let gaps = indices.indices.filter { indices[$0] == nil }
        guard gaps.count <= 1 else { return nil }

        func attempt(_ values: [Int]) -> Opened? {
            var bits = Bits()
            for v in values { bits.append(UInt64(v), width: wordBits) }
            return Frame.open(Frame(bits: bits), tagBits: tagBits, trying: keys)
        }

        func repaired(_ opened: Opened, at position: Int, with value: Int) -> Repaired {
            let heard = words[position]
            let wasMissing = indices[position] == nil
            return Repaired(
                opened: opened, position: position,
                heard: wasMissing ? nil : heard,
                replacement: WordList.word(at: value), wasMissing: wasMissing)
        }

        var values = indices.map { $0 ?? 0 }
        let positions = gaps.isEmpty ? Array(indices.indices) : gaps
        for position in positions {
            let original = values[position]
            for candidate in 0..<WordList.count where candidate != original || gaps.contains(position) {
                values[position] = candidate
                if let opened = attempt(values) {
                    return repaired(opened, at: position, with: candidate)
                }
            }
            values[position] = original
        }
        return nil
    }
}
