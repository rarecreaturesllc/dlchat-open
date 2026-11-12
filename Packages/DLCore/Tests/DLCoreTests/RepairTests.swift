import XCTest
@testable import DLCore

private let keys = Keys(phrase: try! Phrase.generate(words: 10))
private let wrongKeys = Keys(phrase: try! Phrase.generate(words: 10))
private let sentAt = Frame.epoch.addingTimeInterval(300 * 4242)

/// The longest of the T004 sample messages, so the search space is the largest.
private let longText = "doctor needed at the smith house now bring bandages"

private func sealedWords(_ text: String, tagBits: Int) throws -> [String] {
    let body = WordCodec.pad(try TextCodec.encode(text), tagBits: tagBits)
    let frame = try Frame.seal(body: body, sentAt: sentAt, keys: keys, tagBits: tagBits)
    return try WordCodec.encode(frame)
}

/// Any word on the list other than `word`, chosen so the test is repeatable.
private func otherWord(than word: String) -> String {
    let i = WordList.index(of: word)!
    return WordList.word(at: (i + 377) % WordList.count)
}

final class RepairTests: XCTestCase {
    func testRecoversMissingWordAtEveryPosition() throws {
        let words = try sealedWords(longText, tagBits: 64)
        for position in words.indices {
            var heard = words
            heard[position] = Repair.missingMarker
            let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [keys]), "position \(position)")
            XCTAssertEqual(fixed.position, position)
            XCTAssertEqual(fixed.replacement, words[position])
            XCTAssertNil(fixed.heard)
            XCTAssertTrue(fixed.wasMissing)
            XCTAssertEqual(try TextCodec.decode(fixed.opened.body), TextCodec.normalize(longText))
        }
    }

    func testRecoversWrongWordAtEveryPosition() throws {
        let words = try sealedWords("need water at north gate", tagBits: 64)
        for position in words.indices {
            var heard = words
            heard[position] = otherWord(than: words[position])
            let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [keys]), "position \(position)")
            XCTAssertEqual(fixed.position, position)
            XCTAssertEqual(fixed.heard, heard[position])
            XCTAssertEqual(fixed.replacement, words[position])
            XCTAssertFalse(fixed.wasMissing)
            XCTAssertEqual(try TextCodec.decode(fixed.opened.body), "need water at north gate")
        }
    }

    /// Every 23rd value, ending at the last one: the full 1023 takes two minutes in Debug.
    func testManyWrongValuesAtOnePositionAreRecovered() throws {
        let words = try sealedWords("yes", tagBits: 64)
        let position = 5
        let sampled = Array(stride(from: 0, to: WordList.count, by: 23)) + [WordList.count - 1]
        for i in sampled where WordList.word(at: i) != words[position] {
            var heard = words
            heard[position] = WordList.word(at: i)
            let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [keys]), "value \(i)")
            XCTAssertEqual(fixed.replacement, words[position])
        }
    }

    func testWordNotOnTheListCountsAsMissing() throws {
        let words = try sealedWords("meet at the church at noon", tagBits: 64)
        var heard = words
        heard[3] = "notaword"
        let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [keys]))
        XCTAssertEqual(fixed.position, 3)
        XCTAssertTrue(fixed.wasMissing)
        XCTAssertEqual(fixed.replacement, words[3])
    }

    func testRepairsA128BitTagFrame() throws {
        let words = try sealedWords("generator is out of fuel", tagBits: 128)
        var heard = words
        heard[2] = otherWord(than: words[2])
        let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 128, trying: [keys]))
        XCTAssertEqual(fixed.position, 2)
        XCTAssertEqual(fixed.replacement, words[2])
    }

    func testReportsWhichKeysOpenedIt() throws {
        let words = try sealedWords("yes", tagBits: 64)
        var heard = words
        heard[9] = Repair.missingMarker
        let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [wrongKeys, keys]))
        XCTAssertEqual(fixed.opened.keysIndex, 1)
    }

    func testGivesUpOnWhatItCannotFix() throws {
        let words = try sealedWords("need water at north gate", tagBits: 64)

        var twoWrong = words
        twoWrong[1] = otherWord(than: words[1])
        twoWrong[7] = otherWord(than: words[7])
        XCTAssertNil(Repair.search(words: twoWrong, tagBits: 64, trying: [keys]))

        var twoMissing = words
        twoMissing[1] = Repair.missingMarker
        twoMissing[7] = Repair.missingMarker
        XCTAssertNil(Repair.search(words: twoMissing, tagBits: 64, trying: [keys]))

        var wrongOne = words
        wrongOne[4] = otherWord(than: words[4])
        XCTAssertNil(Repair.search(words: wrongOne, tagBits: 64, trying: [wrongKeys]), "wrong group or room")

        XCTAssertNil(Repair.search(words: words, tagBits: 64, trying: [keys]), "intact message needs no repair")
        XCTAssertNil(Repair.search(words: [], tagBits: 64, trying: [keys]))
        XCTAssertNil(Repair.search(words: words, tagBits: 64, trying: []))
    }

    /// Worst case: the longest sample, a wrong word at the very end, so every
    /// candidate is tried. The 2 s limit is for a Release build; Debug is
    /// recorded but allowed ten times as long.
    func testWorstCaseSearchTime() throws {
        let words = try sealedWords(longText, tagBits: 64)
        var heard = words
        heard[words.count - 1] = otherWord(than: words[words.count - 1])
        let start = Date()
        let fixed = try XCTUnwrap(Repair.search(words: heard, tagBits: 64, trying: [keys]))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(fixed.position, words.count - 1)
        print("repair worst case: \(words.count) words, \(String(format: "%.3f", elapsed)) s")
        #if DEBUG
        XCTAssertLessThan(elapsed, 20)
        #else
        XCTAssertLessThan(elapsed, 2)
        #endif
    }
}
