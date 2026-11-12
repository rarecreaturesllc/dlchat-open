import XCTest
@testable import DLCore

final class ComposerTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    private let samples = [
        "yes", "need water at north gate", "meet at the church at noon",
        "doctor needed at the smith house now bring bandages",
        "generator is out of fuel can you spare five gallons",
        "gate code 4417 xylophone", "a", "7",
    ]

    func testLiveCountMatchesRealWordsAndTheyOpen() throws {
        for text in samples {
            let words = try Composer.compose(text: text, keys: keys, sentAt: sentAt)
            XCTAssertEqual(words.count, Composer.wordCount(text: text), text)
            let opened = try XCTUnwrap(Frame.open(try WordCodec.decode(words), tagBits: 64, trying: [keys]), text)
            XCTAssertEqual(try TextCodec.decode(opened.body), TextCodec.normalize(text))
            XCTAssertEqual(opened.sentAt, sentAt)
        }
    }

    func testAToneMessageOverOneBurstThrowsInsteadOfStoppingTheApp() throws {
        let long = String(repeating: "zebra quartz ", count: 160)
        XCTAssertThrowsError(try Composer.composeTone(text: long, keys: keys)) {
            XCTAssertEqual($0 as? ComposerError, .tooLongForSound)
        }
        XCTAssertFalse(try Composer.composeTone(text: "need water at north gate", keys: keys).isEmpty)
    }

    func testCountIsZeroWithoutLettersOrDigits() {
        XCTAssertEqual(Composer.wordCount(text: ""), 0)
        XCTAssertEqual(Composer.wordCount(text: "  \n ?! "), 0)
        XCTAssertThrowsError(try Composer.compose(text: "  ", keys: keys))
    }

    func testCountGrowsWithText() {
        XCTAssertLessThan(Composer.wordCount(text: "yes"), Composer.wordCount(text: samples[4]))
        XCTAssertGreaterThanOrEqual(Composer.wordCount(text: "yes"), 11)
    }

    func testSameTextSoundsDifferentEachTime() throws {
        let a = try Composer.compose(text: samples[1], keys: keys, sentAt: sentAt)
        let b = try Composer.compose(text: samples[1], keys: keys, sentAt: sentAt)
        XCTAssertNotEqual(a, b)
    }
}
