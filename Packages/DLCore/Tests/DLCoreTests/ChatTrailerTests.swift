import XCTest
@testable import DLCore

/// Build 16 adds three things after a Chat message's END: punctuation marks, a reply reference and a
/// call sign, in that order. Each is found by its own marker, so any mix reads back, older readers
/// see the same words, and the frame still fits the radio.
final class ChatTrailerTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 4242)

    private func wire(_ text: String, reply: ReplyTo?, sign: CallSign?) throws -> Data {
        let frame = try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt, replyTo: reply, callSign: sign)
        return NearbyWire.wire(frame: frame, ttl: 0)
    }

    private func read(_ text: String, reply: ReplyTo?, sign: CallSign?) throws -> ReadMessage {
        try XCTUnwrap(Receiver.readNearby(wire: try wire(text, reply: reply, sign: sign), trying: [keys]))
    }

    func testEveryMixOfMarksReplyAndCallSignReadsBack() throws {
        let reply = ReplyTo(sentAt: sentAt, text: "bring water")
        let sign = try XCTUnwrap(CallSign("K9X", color: 6))
        for text in ["meet at the bridge", "meet at the bridge!", "are you ok? yes, coming."] {
            for r in [nil, reply] {
                for s in [nil, sign] {
                    let got = try read(text, reply: r, sign: s)
                    XCTAssertEqual(got.text, text, "\(text) \(r != nil) \(s != nil)")
                    XCTAssertEqual(got.replyTo, r, "\(text) reply")
                    XCTAssertEqual(got.callSign, s, "\(text) call sign")
                }
            }
        }
    }

    func testCarriedWordsKeepReplyAndCallSign() throws {
        let words = try Composer.compose(text: "doctor needed at the smith house", keys: keys, sentAt: sentAt)
        let marker = try XCTUnwrap(ChatCarry.text(words: words))
        let reply = ReplyTo(fingerprint: 0xDEADBEEF)
        let sign = try XCTUnwrap(CallSign("HF", color: 2))
        let got = try read(marker, reply: reply, sign: sign)
        XCTAssertEqual(got.text, marker)
        XCTAssertEqual(got.replyTo, reply)
        XCTAssertEqual(got.callSign, sign)
    }

    /// An older version reads only the words: marks, reply and call sign are padding to it.
    func testOlderReadersSeeTheWords() throws {
        let frame = try Composer.composeNearby(text: "hello there, friend!", keys: keys, sentAt: sentAt,
                                               replyTo: ReplyTo(fingerprint: 7), callSign: CallSign("MK", color: 1))
        let opened = try XCTUnwrap(Frame.open(try XCTUnwrap(Modem.frame(from: frame)), tagBits: QRTransport.tagBits, trying: [keys]))
        XCTAssertEqual(try TextCodec.decode(opened.body), "hello there friend")
    }

    /// All three together cost a few bytes, and an ordinary message with all of them still fits the radio.
    func testAllTrailersStayWithinTheRadioLimit() throws {
        let text = "Meet at the north bridge at noon. Bring water, two radios and the map!"
        let plain = try wire(text.replacingOccurrences(of: "[.,!]", with: "", options: .regularExpression), reply: nil, sign: nil)
        let full = try wire(text, reply: ReplyTo(fingerprint: 1), sign: CallSign("ZZ09", color: 7))
        print("ChatTrailerTests: plain \(plain.count) bytes, with marks + reply + call sign \(full.count) bytes")
        // 3 marks (~8 bytes) + reply (7) + 4-letter call sign (~6), plus padding to whole words.
        XCTAssertLessThanOrEqual(full.count - plain.count, 32, "marks + reply + 4-letter call sign")
        XCTAssertLessThanOrEqual(full.count, Meshtastic.maxPayload)
    }
}
