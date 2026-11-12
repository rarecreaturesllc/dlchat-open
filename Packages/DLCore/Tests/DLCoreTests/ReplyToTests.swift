import XCTest
@testable import DLCore

/// A Chat reply: the reference to the earlier message is sealed in after the text and read back.
final class ReplyToTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    private func chat(_ text: String, replyTo: ReplyTo?, flags: UInt8 = 0) throws -> ReadMessage {
        let frame = try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt, flags: flags, replyTo: replyTo)
        return try XCTUnwrap(Receiver.readNearby(wire: NearbyWire.wire(frame: frame, ttl: 0), trying: [keys]))
    }

    func testReplyRoundTripsAndPointsAtTheOriginal() throws {
        let original = try chat("meet at the bridge?", replyTo: nil)
        let ref = ReplyTo(sentAt: original.sentAt, text: original.text)
        let reply = try chat("on my way!", replyTo: ref)
        XCTAssertEqual(reply.replyTo, ref)
        XCTAssertEqual(reply.text, "on my way!", "marks ride along with the reply")
        // The sender and every receiver compute the same reference from what they hold.
        XCTAssertEqual(ReplyTo(sentAt: original.sentAt, text: original.text).fingerprint, ref.fingerprint)
    }

    func testFingerprintDependsOnTextAndSlot() {
        let a = ReplyTo(sentAt: sentAt, text: "ok")
        XCTAssertEqual(a, ReplyTo(sentAt: sentAt.addingTimeInterval(299), text: "ok"))
        XCTAssertNotEqual(a, ReplyTo(sentAt: sentAt.addingTimeInterval(300), text: "ok"))
        XCTAssertNotEqual(a, ReplyTo(sentAt: sentAt, text: "ok."))
    }

    func testEdgeFingerprintsAndShortFlaggedMessages() throws {
        for fingerprint: UInt32 in [0, 1, 0xFFFF_FFFF, 0x8000_0001] {
            let read = try chat("ok", replyTo: ReplyTo(fingerprint: fingerprint), flags: 3)
            XCTAssertEqual(read.replyTo?.fingerprint, fingerprint)
            XCTAssertEqual(read.text, "ok")
            XCTAssertTrue(read.duress)
            XCTAssertTrue(read.readOnce)
        }
    }

    func testNoReplyReadsAsNone() throws {
        // Padding is random, so try many seals of the shortest message, where padding is longest.
        for _ in 0..<200 { XCTAssertNil(try chat("ok", replyTo: nil).replyTo) }
    }

    /// An older version reads only the text and ignores the reference after it.
    func testOlderReadersSeeTheSameText() throws {
        let frame = try Composer.composeNearby(text: "hello there", keys: keys, sentAt: sentAt, replyTo: ReplyTo(fingerprint: 42))
        let opened = try XCTUnwrap(Frame.open(try XCTUnwrap(Modem.frame(from: frame)), tagBits: QRTransport.tagBits, trying: [keys]))
        XCTAssertEqual(try TextCodec.decode(opened.body), "hello there")
    }

    func testCarriedWordsAndSoundKeepTheirFrameAndReply() throws {
        let ref = ReplyTo(fingerprint: 0xC0FFEE)
        let words = try Composer.compose(text: "doctor needed at the smith house", keys: keys, sentAt: sentAt)
        let wordsText = try XCTUnwrap(ChatCarry.text(words: words))
        let read = try chat(wordsText, replyTo: ref)
        XCTAssertEqual(read.text, wordsText)
        XCTAssertEqual(read.replyTo, ref)

        let tone = try Composer.composeToneFrame(text: "doctor needed", keys: keys, sentAt: sentAt)
        let soundText = try XCTUnwrap(ChatCarry.text(.sound, frame: tone))
        let heard = try chat(soundText, replyTo: ref)
        XCTAssertEqual(ChatCarry.parse(heard.text)?.frame, tone)
        XCTAssertEqual(heard.replyTo, ref)
    }

    /// Typing a marker word itself does not turn the reference into a carried frame.
    func testMarkerWordAsPlainTextStaysPlain() throws {
        let ref = ReplyTo(fingerprint: 0xFFFF_FFFF)
        for text in ["dlwords", "dlsound"] {
            let read = try chat(text, replyTo: ref)
            XCTAssertEqual(read.text, text)
            XCTAssertEqual(read.replyTo, ref)
        }
    }

    func testReplyIsSealedAndSmallEnoughForTheRadio() throws {
        let ref = ReplyTo(fingerprint: 7)
        let frame = try Composer.composeNearby(text: "meet at the bridge", keys: keys, sentAt: sentAt, replyTo: ref)
        XCTAssertNil(Receiver.readNearby(wire: NearbyWire.wire(frame: frame, ttl: 0), trying: [other]))
        let plain = try Composer.composeNearby(text: "meet at the bridge", keys: keys, sentAt: sentAt)
        XCTAssertLessThanOrEqual(frame.count - plain.count, 8)
        XCTAssertLessThanOrEqual(frame.count + 1, Meshtastic.maxPayload)
    }
}
