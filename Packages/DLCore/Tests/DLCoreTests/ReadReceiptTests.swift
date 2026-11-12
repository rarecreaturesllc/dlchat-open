import XCTest
@testable import DLCore

/// Read receipts: sealed under their own keys, small enough for the radio, invisible to older versions.
final class ReadReceiptTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 4242)

    private func message(_ text: String, keys: Keys) throws -> ReadMessage {
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt), ttl: 0)
        return try XCTUnwrap(Receiver.readNearby(wire: wire, trying: [keys]))
    }

    func testReceiptRoundTrips() throws {
        let refs: [UInt64] = [1, 0xFF_FFFF_FFFF, 0x12_3456_789A]
        let wire = try ReadReceipt.wire(reader: 0xBEEF, refs: refs, keys: keys.receiptKeys, sentAt: sentAt)
        let opened = try XCTUnwrap(ReadReceipt.open(wire: wire, trying: [other.receiptKeys, keys.receiptKeys]))
        XCTAssertEqual(opened.reader, 0xBEEF)
        XCTAssertEqual(opened.refs, refs)
        XCTAssertEqual(opened.keysIndex, 1)
    }

    func testFullReceiptFitsOneRadioMessage() throws {
        let refs = (0..<UInt64(ReadReceipt.maxRefs)).map { $0 * 0x1_0000_0001 }
        let wire = try ReadReceipt.wire(reader: 1, refs: refs, keys: keys.receiptKeys)
        XCTAssertLessThanOrEqual(wire.count, Meshtastic.maxPayload)
        XCTAssertEqual(ReadReceipt.open(wire: wire, trying: [keys.receiptKeys])?.refs, refs)
        XCTAssertThrowsError(try ReadReceipt.wire(reader: 1, refs: refs + [1], keys: keys.receiptKeys))
        XCTAssertThrowsError(try ReadReceipt.wire(reader: 1, refs: [], keys: keys.receiptKeys))
    }

    /// Older versions (and this one's message path) try only room keys, so a receipt never shows as a message.
    func testReceiptIsNotAMessageAndAMessageIsNotAReceipt() throws {
        let wire = try ReadReceipt.wire(reader: 7, refs: [42], keys: keys.receiptKeys)
        XCTAssertNil(Receiver.readNearby(wire: wire, trying: [keys, Keys(masterData: keys.masterData, room: "north")]))
        XCTAssertNil(ReadReceipt.open(wire: wire, trying: [other.receiptKeys]))
        let chat = NearbyWire.wire(frame: try Composer.composeNearby(text: "hello", keys: keys), ttl: 0)
        XCTAssertNil(ReadReceipt.open(wire: chat, trying: [keys.receiptKeys]))
    }

    /// Sender and reader compute the same reference from what each opened; any change gives another.
    func testRefIsTheSameOnBothPhonesAndDiffersPerMessage() throws {
        let sent = try message("need water at north gate", keys: keys)
        let heard = try XCTUnwrap(Receiver.readNearby(
            wire: NearbyWire.wire(frame: try Composer.composeNearby(text: "need water at north gate", keys: keys, sentAt: sentAt), ttl: 0),
            trying: [keys]))
        XCTAssertEqual(ReadReceipt.ref(of: sent, room: "North "), ReadReceipt.ref(of: sent, room: "north"))
        XCTAssertNotEqual(ReadReceipt.ref(of: sent, room: ""), ReadReceipt.ref(of: sent, room: "north"))
        // Same words sealed twice get different salts (63 in 64 times), so different refs.
        if sent.salt != heard.salt { XCTAssertNotEqual(ReadReceipt.ref(of: sent, room: ""), ReadReceipt.ref(of: heard, room: "")) }
        XCTAssertLessThan(ReadReceipt.ref(of: sent, room: ""), 1 << 40)
    }
}
