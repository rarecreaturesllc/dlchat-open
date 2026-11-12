import XCTest
@testable import DLCore

/// Send > Encrypt Words / Encrypt Sound posted in Chat, then opened in Receive.
final class ChatCarryTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)
    private let long = "doctor needed at the smith house now bring bandages and clean water"

    private func chat(_ text: String) throws -> ReadMessage {
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt), ttl: 0)
        return try XCTUnwrap(Receiver.readNearby(wire: wire, trying: [keys]))
    }

    func testWordsRoundTripThroughChatAndOpenInReceive() throws {
        let words = try Composer.compose(text: long, keys: keys, sentAt: sentAt)
        let text = try XCTUnwrap(ChatCarry.text(words: words))
        XCTAssertEqual(text, "dlwords " + words.joined(separator: " "))
        let received = try chat(text)
        XCTAssertEqual(received.text, text)
        let carried = try XCTUnwrap(ChatCarry.parse(received.text))
        XCTAssertEqual(carried.kind, .words)
        XCTAssertEqual(carried.words, words)
        let opened = try XCTUnwrap(Receiver.read(words: carried.words, trying: [keys]))
        XCTAssertEqual(opened.text, TextCodec.normalize(long))
    }

    func testSoundRoundTripThroughChatAndOpensAsHeardTones() throws {
        let frame = try Composer.composeToneFrame(text: long, keys: keys, sentAt: sentAt, flags: 2)
        let text = try XCTUnwrap(ChatCarry.text(.sound, frame: frame))
        let carried = try XCTUnwrap(ChatCarry.parse(try chat(text).text))
        XCTAssertEqual(carried.kind, .sound)
        XCTAssertEqual(carried.frame, frame)
        // What the speaker plays decodes to the same bytes the chat carried.
        let heard = try XCTUnwrap(Modem.frame(from: carried.payload))
        let opened = try XCTUnwrap(Receiver.readTone(payload: Data(heard.bits.bytes), trying: [keys]))
        XCTAssertEqual(opened.text, TextCodec.normalize(long))
        XCTAssertTrue(opened.readOnce)
        XCTAssertNil(Receiver.readTone(payload: carried.payload, trying: [other]))
        let samples = Modem.encode(carried.frame)
        XCTAssertEqual(Modem.duration(bytes: carried.payload.count), Double(samples.count) / Modem.sampleRate, accuracy: 1e-9)
    }

    /// Raw bits, not spelled letters: a long message's words still fit one radio packet.
    func testCarriedWordsFitTheRadio() throws {
        let words = try Composer.compose(text: long, keys: keys, sentAt: sentAt)
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: ChatCarry.text(words: words)!, keys: keys), ttl: 4)
        XCTAssertLessThanOrEqual(wire.count, Meshtastic.maxPayload)
        let spelled = try Composer.composeNearby(text: "carried " + words.joined(separator: " "), keys: keys)
        XCTAssertLessThan(wire.count, spelled.count)
    }

    func testOrdinaryTextIsNotCarried() throws {
        for text in ["dlwords", "dlwords hello there", "sound check at noon", "dlsound"] {
            XCTAssertNil(ChatCarry.parse(text), text)
            XCTAssertEqual(try chat(text).text, TextCodec.normalize(text), text)
        }
        XCTAssertNil(ChatCarry.text(words: ["notalistword"]))
    }
}
