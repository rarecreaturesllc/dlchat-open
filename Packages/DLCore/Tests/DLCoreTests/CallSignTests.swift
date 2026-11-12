import XCTest
@testable import DLCore

/// A call sign sealed into a Chat message and read back by the friend who opens it.
final class CallSignTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    private func chat(_ text: String, sign: CallSign?, flags: UInt8 = 0) throws -> ReadMessage {
        let frame = try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt, flags: flags, callSign: sign)
        return try XCTUnwrap(Receiver.readNearby(wire: NearbyWire.wire(frame: frame, ttl: 0), trying: [keys]))
    }

    func testCleaningKeepsUpToFourLettersOrDigits() {
        XCTAssertEqual(CallSign.clean("hf"), "HF")
        XCTAssertEqual(CallSign.clean("k-9 x!"), "K9X")
        XCTAssertEqual(CallSign.clean("abcdef"), "ABCD")
        XCTAssertEqual(CallSign.clean("é✓ "), "")
        XCTAssertNil(CallSign("  "))
        XCTAssertNil(CallSign("AB", color: 8))
        XCTAssertNil(CallSign("AB", color: -1))
    }

    func testEveryLengthAndColourRoundTrips() throws {
        for letters in ["A", "HF", "K9X", "ZZ09"] {
            for color in 0..<CallSign.colors {
                let sign = try XCTUnwrap(CallSign(letters, color: color))
                let read = try chat("meet at the bridge", sign: sign)
                XCTAssertEqual(read.callSign, sign, "\(letters) \(color)")
                XCTAssertEqual(read.text, "meet at the bridge")
            }
        }
    }

    func testShortMessagesAndFlagsKeepTheirMeaning() throws {
        let sign = try XCTUnwrap(CallSign("HF", color: 3))
        let read = try chat("ok", sign: sign, flags: 3)
        XCTAssertEqual(read.text, "ok")
        XCTAssertEqual(read.callSign, sign)
        XCTAssertTrue(read.duress)
        XCTAssertTrue(read.readOnce)
    }

    func testNoCallSignReadsAsNone() throws {
        // Padding is random, so try many seals of the shortest message, where padding is longest.
        for _ in 0..<200 { XCTAssertNil(try chat("ok", sign: nil).callSign) }
    }

    /// An older version reads only the text and ignores the call sign after it.
    func testOlderReadersSeeTheSameText() throws {
        let sign = try XCTUnwrap(CallSign("MK", color: 1))
        let frame = try Composer.composeNearby(text: "hello there", keys: keys, sentAt: sentAt, callSign: sign)
        let opened = try XCTUnwrap(Frame.open(try XCTUnwrap(Modem.frame(from: frame)), tagBits: QRTransport.tagBits, trying: [keys]))
        XCTAssertEqual(try TextCodec.decode(opened.body), "hello there")
    }

    func testCarriedWordsAndSoundKeepTheirFrameAndCallSign() throws {
        let sign = try XCTUnwrap(CallSign("BR", color: 5))
        let words = try Composer.compose(text: "doctor needed at the smith house", keys: keys, sentAt: sentAt)
        let wordsText = try XCTUnwrap(ChatCarry.text(words: words))
        let read = try chat(wordsText, sign: sign)
        XCTAssertEqual(read.text, wordsText)
        XCTAssertEqual(read.callSign, sign)

        let tone = try Composer.composeToneFrame(text: "doctor needed", keys: keys, sentAt: sentAt)
        let soundText = try XCTUnwrap(ChatCarry.text(.sound, frame: tone))
        let heard = try chat(soundText, sign: sign)
        XCTAssertEqual(ChatCarry.parse(heard.text)?.frame, tone)
        XCTAssertEqual(heard.callSign, sign)
    }

    /// Typing the marker word itself does not turn the call sign into a carried frame.
    func testMarkerWordAsPlainTextStaysPlain() throws {
        let sign = try XCTUnwrap(CallSign("ZZ09", color: 7))
        for text in ["dlwords", "dlsound"] {
            let read = try chat(text, sign: sign)
            XCTAssertEqual(read.text, text)
            XCTAssertEqual(read.callSign, sign)
        }
    }

    func testCallSignIsSealedAndFitsTheRadio() throws {
        let sign = try XCTUnwrap(CallSign("ZZ09", color: 7))
        let frame = try Composer.composeNearby(text: "meet at the bridge", keys: keys, sentAt: sentAt, callSign: sign)
        XCTAssertNil(Receiver.readNearby(wire: NearbyWire.wire(frame: frame, ttl: 0), trying: [other]))
        let plain = try Composer.composeNearby(text: "meet at the bridge", keys: keys, sentAt: sentAt)
        XCTAssertLessThanOrEqual(frame.count - plain.count, 7)
        XCTAssertLessThanOrEqual(frame.count + 1, Meshtastic.maxPayload)
    }
}
