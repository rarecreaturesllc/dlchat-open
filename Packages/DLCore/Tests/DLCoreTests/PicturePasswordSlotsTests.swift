import XCTest
@testable import DLCore

/// The numbered boxes a friend types a picture invite password into.
final class PicturePasswordSlotsTests: XCTestCase {
    func testStartsWithFiveEmptyBoxesAndStaysWithinFiveToSix() {
        var slots = PicturePasswordSlots()
        XCTAssertEqual(slots.words, ["", "", "", "", ""])
        XCTAssertTrue(slots.isEmpty)
        slots.resize(to: 6)
        XCTAssertEqual(slots.count, 6)
        slots.resize(to: 9)
        XCTAssertEqual(slots.count, 6)
        slots.resize(to: 2)
        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(PicturePasswordSlots(count: 6).count, 6)
    }

    func testOneWordStaysInItsBox() {
        var slots = PicturePasswordSlots()
        XCTAssertNil(slots.enter("map", at: 0))
        XCTAssertNil(slots.enter("maple", at: 0))
        XCTAssertEqual(slots.words[0], "maple")
        XCTAssertNil(slots.enter("", at: 0))
        XCTAssertEqual(slots.words[0], "")
    }

    func testASpaceMovesToTheNextBox() {
        var slots = PicturePasswordSlots()
        XCTAssertEqual(slots.enter("maple ", at: 0), 1)
        XCTAssertEqual(slots.words, ["maple", "", "", "", ""])
        // In the last box there is nowhere to go, so it stays.
        XCTAssertEqual(slots.enter("badge ", at: 4), 4)
        XCTAssertEqual(slots.words[4], "badge")
    }

    func testPastedWordsFillTheBoxesInOrder() {
        var slots = PicturePasswordSlots()
        XCTAssertEqual(slots.enter("Maple river, stone owl badge", at: 0), 4)
        XCTAssertEqual(slots.words, ["Maple", "river", "stone", "owl", "badge"])
        XCTAssertEqual(slots.password, "maple river stone owl badge")
        // Pasted from box 3 onward: boxes 1 and 2 keep what was typed.
        var later = PicturePasswordSlots()
        later.enter("maple", at: 0)
        later.enter("river", at: 1)
        XCTAssertEqual(later.enter("stone owl badge", at: 2), 4)
        XCTAssertEqual(later.password, "maple river stone owl badge")
    }

    func testSixPastedWordsAddTheSixthBox() {
        var slots = PicturePasswordSlots()
        XCTAssertEqual(slots.enter("maple river stone owl badge foam", at: 0), 5)
        XCTAssertEqual(slots.count, 6)
        XCTAssertEqual(slots.words[5], "foam")
    }

    func testExtraWordsAreKeptNotDropped() {
        var slots = PicturePasswordSlots()
        slots.enter("a b c d e f g", at: 0)
        XCTAssertEqual(slots.count, 6)
        XCTAssertEqual(slots.words[5], "f g")
        XCTAssertEqual(slots.password, "a b c d e f g")
    }

    func testShrinkingDropsTheLastWord() {
        var slots = PicturePasswordSlots()
        slots.enter("maple river stone owl badge foam", at: 0)
        slots.resize(to: 5)
        XCTAssertEqual(slots.password, "maple river stone owl badge")
    }

    func testBoxesUnlockTheSamePictureAsTheSendersWords() throws {
        let phrase = try Phrase.generate(words: 10)
        for count in PictureInvite.passwordWordCounts {
            let words = PictureInvite.makePassword(words: count)
            let payload = try XCTUnwrap(PictureInvite.read(try PictureInvite.render(phrase: phrase, name: "Porch", password: words.joined(separator: " "))))
            var slots = PicturePasswordSlots(count: count)
            for (index, word) in words.enumerated() { slots.enter(word.uppercased(), at: index) }
            XCTAssertEqual(try PictureInvite.unlock(payload, password: slots.password).phrase, phrase)
            // Out of order does not open it.
            var swapped = PicturePasswordSlots(count: count)
            for (index, word) in words.reversed().enumerated() { swapped.enter(word, at: index) }
            if words != words.reversed() {
                XCTAssertThrowsError(try PictureInvite.unlock(payload, password: swapped.password))
            }
        }
    }

    /// Pictures made with four words (before the five-word minimum) still open: four boxes filled, the
    /// last left empty.
    func testOlderFourWordPictureOpensWithTheLastBoxEmpty() throws {
        let phrase = try Phrase.generate(words: 10)
        let four = "maple river stone owl"
        let payload = try XCTUnwrap(PictureInvite.read(try PictureInvite.render(phrase: phrase, name: "", password: four)))
        var slots = PicturePasswordSlots()
        for (index, word) in four.split(separator: " ").enumerated() { slots.enter(String(word), at: index) }
        XCTAssertEqual(slots.password, four)
        XCTAssertEqual(try PictureInvite.unlock(payload, password: slots.password).phrase, phrase)
    }
}
