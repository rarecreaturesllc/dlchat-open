import Foundation

/// The 1024 radio-distinct words, 10 bits each. Part of the wire format: the
/// file's SHA-256 is pinned in the tests, and the order (alphabetical) is the
/// word-to-number mapping. Built by `tools/make_wordlist.py`.
public enum WordList {
    public static let count = 1024
    public static let bitsPerWord = 10

    static let resourceURL = Bundle.module.url(forResource: "words", withExtension: "txt")

    /// Words in index order. Crashes at launch if the resource is missing or
    /// malformed, since nothing works without it.
    public static let words: [String] = {
        guard let url = resourceURL,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("words.txt missing from DLCore resources") }
        let list = text.split(separator: "\n").map(String.init)
        precondition(list.count == count, "words.txt must hold exactly \(count) words")
        return list
    }()

    private static let indexes: [String: Int] = {
        Dictionary(uniqueKeysWithValues: words.enumerated().map { ($1, $0) })
    }()

    /// Index of a word, ignoring case, or nil if it is not on the list.
    public static func index(of word: String) -> Int? {
        indexes[word.lowercased()]
    }

    public static func word(at index: Int) -> String {
        words[index]
    }
}
