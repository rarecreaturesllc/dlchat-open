import CryptoKit
import XCTest
@testable import DLCore

final class WordListTests: XCTestCase {
    /// SHA-256 of Resources/words.txt. Changing the list splits every group, so
    /// this only changes together with a protocol version bump.
    private static let pinnedSHA256 = "5546897b5bdd6a03a6abf1703f89be0034eddf31d9b7245dea17e2ee12ee53f9"

    func testExactly1024UniqueLowercaseWords() {
        let words = WordList.words
        XCTAssertEqual(words.count, 1024)
        XCTAssertEqual(Set(words).count, 1024)
        XCTAssertEqual(words, words.sorted())
        for word in words {
            XCTAssertNotNil(word.range(of: "^[a-z]{4,8}$", options: .regularExpression), word)
        }
    }

    func testFileHashIsPinned() throws {
        let url = try XCTUnwrap(WordList.resourceURL)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, Self.pinnedSHA256)
    }

    func testNoSharedPhoneticKey() {
        var seen: [String: String] = [:]
        for word in WordList.words {
            let key = Self.phoneticKey(word)
            if let other = seen[key] {
                XCTFail("\(word) and \(other) share phonetic key \(key)")
            }
            seen[key] = word
        }
    }

    func testNoPairAtEditDistanceOne() {
        let words = WordList.words
        for i in words.indices {
            for j in words.indices where j > i {
                let a = Array(words[i]), b = Array(words[j])
                guard abs(a.count - b.count) <= 1 else { continue }
                XCTAssertGreaterThan(Self.editDistance(a, b), 1, "\(words[i]) / \(words[j])")
            }
        }
    }

    func testLookup() {
        XCTAssertEqual(WordList.index(of: WordList.words[0]), 0)
        XCTAssertEqual(WordList.index(of: WordList.words[1023].uppercased()), 1023)
        XCTAssertNil(WordList.index(of: "xyzzy"))
        XCTAssertEqual(WordList.word(at: 5), WordList.words[5])
    }

    // Written separately from tools/make_wordlist.py so the two check each other.
    private static func phoneticKey(_ word: String) -> String {
        var w = word
        for (a, b) in [("ph", "f"), ("ck", "k"), ("qu", "kw"), ("wr", "r"), ("kn", "n"), ("gh", ""),
                       ("wh", "w"), ("tch", "ch"), ("sh", "S"), ("ch", "C"), ("th", "T")] {
            w = w.replacingOccurrences(of: a, with: b)
        }
        w = w.replacingOccurrences(of: "c(?=[eiy])", with: "s", options: .regularExpression)
        for (a, b) in [("c", "k"), ("z", "s"), ("v", "f"), ("d", "t"), ("b", "p"), ("g", "k")] {
            w = w.replacingOccurrences(of: a, with: b)
        }
        w = w.replacingOccurrences(of: "(.)\\1+", with: "$1", options: .regularExpression)
        guard let first = w.first else { return "" }
        let rest = String(w.dropFirst()).replacingOccurrences(of: "[aeiouy]", with: "", options: .regularExpression)
        return String(first) + rest
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
