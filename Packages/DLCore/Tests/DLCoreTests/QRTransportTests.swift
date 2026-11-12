import XCTest
@testable import DLCore

final class QRTransportTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    func testPayloadRoundTripsEveryFrameLength() throws {
        for length in 1...60 {
            let text = String(repeating: "a", count: length)
            let payload = try Composer.composeQR(text: text, keys: keys, sentAt: sentAt)
            let frame = try XCTUnwrap(QRTransport.frame(from: payload), "length \(length)")
            XCTAssertEqual(QRTransport.payload(for: frame), payload)
            XCTAssertEqual(frame.bits.count % WordList.bitsPerWord, 0)
        }
    }

    func testScannedMessageOpensWithTheGroupKeysAndShowsTheSendTime() throws {
        let payload = try Composer.composeQR(text: "need water at north gate", keys: keys, sentAt: sentAt, flags: 1)
        let message = try XCTUnwrap(Receiver.readQR(payload: payload, trying: [other, keys]))
        XCTAssertEqual(message.text, "need water at north gate")
        XCTAssertEqual(message.sentAt, sentAt)
        XCTAssertEqual(message.keysIndex, 1)
        XCTAssertTrue(message.duress)
    }

    func testWrongGroupFailsAndSurroundingSpaceIsIgnored() throws {
        let payload = try Composer.composeQR(text: "hello", keys: keys, sentAt: sentAt)
        XCTAssertNil(Receiver.readQR(payload: payload, trying: [other]))
        XCTAssertNotNil(Receiver.readQR(payload: " \(payload)\n", trying: [keys]))
    }

    func testAnyChangedCharacterFailsToOpen() throws {
        let payload = try Composer.composeQR(text: "hello", keys: keys, sentAt: sentAt)
        let chars = Array(payload)
        // The last character can carry only spare bits that the decoder drops, so it is skipped.
        for i in chars.indices.dropLast() {
            var changed = chars
            changed[i] = chars[i] == "A" ? "B" : "A"
            XCTAssertNil(Receiver.readQR(payload: String(changed), trying: [keys]), "character \(i)")
        }
    }

    func testOtherQRContentIsNotAFrame() throws {
        for text in ["", "https://example.com", "WIFI:S:net;T:WPA;P:pw;;", "hello world", "é", "AAAA"] {
            XCTAssertNil(QRTransport.frame(from: text), text)
        }
        let phrase = try Phrase.generate(words: 10).text
        XCTAssertNil(QRTransport.frame(from: phrase))
    }

    func testSameTextGivesDifferentCodesAndTheCodeIsPlainAscii() throws {
        let a = try Composer.composeQR(text: "same", keys: keys, sentAt: sentAt)
        let b = try Composer.composeQR(text: "same", keys: keys, sentAt: sentAt)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }
}
