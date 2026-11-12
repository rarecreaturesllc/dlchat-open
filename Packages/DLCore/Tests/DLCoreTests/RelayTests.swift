import XCTest
@testable import DLCore

final class RelayTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))
    private let other = Keys(phrase: try! Phrase.generate(words: 10))
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let sentAt = Frame.epoch.addingTimeInterval(300 * 777)

    private func frameBytes(_ text: String = "relay test") throws -> Data {
        try Composer.composeNearby(text: text, keys: keys, sentAt: sentAt)
    }

    func testWireRoundTripAndRejectsNonFrames() throws {
        let frame = try frameBytes()
        let parsed = try XCTUnwrap(NearbyWire.parse(NearbyWire.wire(frame: frame, ttl: 3)))
        XCTAssertEqual(parsed.ttl, 3)
        XCTAssertEqual(parsed.frame, frame)
        XCTAssertNil(NearbyWire.parse(Data()))
        XCTAssertNil(NearbyWire.parse(Data([3, 1, 2, 3])))
        XCTAssertNil(NearbyWire.parse(Data(repeating: 7, count: NearbyWire.maxBytes + 1)))
    }

    func testIncomingHopCountIsCappedToStartTTL() throws {
        let frame = try frameBytes()
        for ttl: UInt8 in [NearbyWire.startTTL + 1, 100, 255] {
            let parsed = try XCTUnwrap(NearbyWire.parse(NearbyWire.wire(frame: frame, ttl: ttl)))
            XCTAssertEqual(parsed.ttl, NearbyWire.startTTL)
        }
        XCTAssertEqual(NearbyWire.parse(NearbyWire.wire(frame: frame, ttl: NearbyWire.startTTL))?.ttl, NearbyWire.startTTL)
    }

    func testReadNearbyOpensForGroupOnly() throws {
        let wire = NearbyWire.wire(frame: try frameBytes("meet at dawn"), ttl: 2)
        XCTAssertEqual(Receiver.readNearby(wire: wire, trying: [other, keys])?.text, "meet at dawn")
        XCTAssertNil(Receiver.readNearby(wire: wire, trying: [other]))
    }
}
