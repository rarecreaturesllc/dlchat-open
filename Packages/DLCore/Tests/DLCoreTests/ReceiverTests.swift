import XCTest
@testable import DLCore

final class ReceiverTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)
    private let text = "need water at north gate"

    private func words(flags: UInt8 = 0) throws -> [String] {
        try Composer.compose(text: text, keys: keys, sentAt: sentAt, flags: flags)
    }

    func testReadsHeardWordsAndNamesTheGroupThatOpenedThem() throws {
        let message = try XCTUnwrap(Receiver.read(words: try words(), trying: [other, keys]))
        XCTAssertEqual(message.text, text)
        XCTAssertEqual(message.sentAt, sentAt)
        XCTAssertEqual(message.keysIndex, 1)
        XCTAssertNil(message.repair)
        XCTAssertFalse(message.duress)
    }

    func testCaseIsIgnoredAndWrongGroupFails() throws {
        let heard = try words().map { $0.uppercased() }
        XCTAssertEqual(Receiver.read(words: heard, trying: [keys])?.text, text)
        XCTAssertNil(Receiver.read(words: heard, trying: [other]))
    }

    func testReadOnceFlagIsBitOneAndIndependentOfDuress() throws {
        let once = try XCTUnwrap(Receiver.read(words: try words(flags: 2), trying: [keys]))
        XCTAssertTrue(once.readOnce)
        XCTAssertFalse(once.duress)
        let both = try XCTUnwrap(Receiver.read(words: try words(flags: 3), trying: [keys]))
        XCTAssertTrue(both.readOnce && both.duress)
        XCTAssertEqual(Receiver.read(words: try words(flags: 0), trying: [keys])?.readOnce, false)
    }

    func testDuressFlagIsReported() throws {
        XCTAssertEqual(Receiver.read(words: try words(flags: 1), trying: [keys])?.duress, true)
    }

    func testFewWordsAndPartialMessagesGiveNothing() throws {
        let all = try words()
        XCTAssertNil(Receiver.read(words: Array(all.prefix(Receiver.minimumWords - 1)), trying: [keys]))
        XCTAssertNil(Receiver.read(words: Array(all.dropLast()), trying: [keys]))
    }

    func testMissingWordIsRepairedAndLabelled() throws {
        var heard = try words()
        let original = heard[7]
        heard[7] = "?"
        XCTAssertNil(Receiver.read(words: heard, trying: [keys]))
        let message = try XCTUnwrap(Receiver.repair(words: heard, trying: [keys]))
        XCTAssertEqual(message.text, text)
        XCTAssertEqual(message.repair?.position, 7)
        XCTAssertEqual(message.repair?.replacement, original)
        XCTAssertEqual(message.repair?.wasMissing, true)
    }

    func testWrongWordIsRepairedAndNamed() throws {
        var heard = try words()
        let original = heard[3]
        heard[3] = WordList.word(at: (WordList.index(of: original)! + 1) % WordList.count)
        let message = try XCTUnwrap(Receiver.repair(words: heard, trying: [keys]))
        XCTAssertEqual(message.repair?.heard, heard[3])
        XCTAssertEqual(message.repair?.replacement, original)
        XCTAssertEqual(message.repair?.wasMissing, false)
    }

    func testTwoGapsCannotBeRepaired() throws {
        var heard = try words()
        heard[2] = "?"
        heard[5] = "?"
        XCTAssertEqual(Receiver.gapCount(in: heard), 2)
        XCTAssertNil(Receiver.repair(words: heard, trying: [keys]))
    }

    func testSuggestions() {
        XCTAssertTrue(Receiver.suggestions(prefix: "").isEmpty)
        XCTAssertTrue(Receiver.suggestions(prefix: "?").isEmpty)
        let first = WordList.word(at: 100)
        let prefix = String(first.prefix(2))
        let found = Receiver.suggestions(prefix: prefix.uppercased(), limit: 1024)
        XCTAssertTrue(found.contains(first))
        XCTAssertTrue(found.allSatisfy { $0.hasPrefix(prefix) })
        XCTAssertLessThanOrEqual(Receiver.suggestions(prefix: prefix).count, 6)
    }

    func testTimeNotes() {
        let now = Date()
        XCTAssertEqual(Receiver.timeNote(sentAt: now.addingTimeInterval(-3600), now: now), .normal)
        XCTAssertEqual(Receiver.timeNote(sentAt: now.addingTimeInterval(-90_000), now: now), .old)
        XCTAssertEqual(Receiver.timeNote(sentAt: now.addingTimeInterval(1_000), now: now), .clockMayDiffer)
        XCTAssertEqual(Receiver.timeNote(sentAt: now.addingTimeInterval(120), now: now), .normal)
    }
}
