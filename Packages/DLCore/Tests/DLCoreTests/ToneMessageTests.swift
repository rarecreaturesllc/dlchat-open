import XCTest
@testable import DLCore

final class ToneMessageTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    func testSealedMessageSurvivesTheModemAndOpensWithTheGroupKeys() throws {
        let samples = try Composer.composeTone(text: "need water at north gate", keys: keys, sentAt: sentAt, flags: 1)
        let decoder = ModemDecoder()
        let bursts = decoder.feed(samples + [Float](repeating: 0, count: 4_000))
        XCTAssertEqual(bursts.count, 1)
        let message = try XCTUnwrap(Receiver.readTone(payload: bursts[0], trying: [other, keys]))
        XCTAssertEqual(message.text, "need water at north gate")
        XCTAssertEqual(message.sentAt, sentAt)
        XCTAssertEqual(message.keysIndex, 1)
        XCTAssertTrue(message.duress)
    }

    func testWrongGroupAndNonFramesAreNotRead() throws {
        let samples = try Composer.composeTone(text: "hello", keys: keys, sentAt: sentAt)
        let burst = try XCTUnwrap(ModemDecoder().feed(samples + [Float](repeating: 0, count: 4_000)).first)
        XCTAssertNil(Receiver.readTone(payload: burst, trying: [other]))
        XCTAssertNil(Receiver.readTone(payload: Data([1, 2, 3]), trying: [keys]))
    }

    func testBurstLengthStaysUnderTheBlueprintBudgetForAShortMessage() throws {
        let samples = try Composer.composeTone(text: "need water at north gate", keys: keys, sentAt: sentAt)
        XCTAssertLessThan(Double(samples.count) / Modem.sampleRate, 10)
    }
}
