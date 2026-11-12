import DLCore
import XCTest
@testable import DLChat

@MainActor
final class RelayPoolTests: XCTestCase {
    private let keys = Keys(masterData: Data(repeating: 7, count: 32))

    private func event(_ text: String) throws -> Online.Event {
        try Online.event(wire: NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys), ttl: 0), keys: keys)
    }

    func testPublishIsAcceptedAndSubscribersReceive() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let sender = RelayPool(), receiver = RelayPool()
        var got: [Online.Event] = []
        receiver.onEvent = { got.append($0) }
        receiver.connect([relay.url])
        receiver.subscribe(Online.filter(mailboxes: Online.mailboxes(for: keys, now: Date()), since: Date().addingTimeInterval(-3 * 86_400)))
        sender.connect([relay.url])
        let sent = try event("meet at the bridge")
        let accepted = await sender.publish(sent)
        XCTAssertEqual(accepted, 1)
        for _ in 0..<50 where got.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(got.first, sent)
        XCTAssertEqual(Receiver.readNearby(wire: try XCTUnwrap(Online.wire(from: got[0], trying: [keys])).wire, trying: [keys])?.text, "meet at the bridge")
        sender.disconnect(); receiver.disconnect()
    }

    func testStoredEventsArriveOnSubscribeAndRejectsCount() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let sender = RelayPool()
        sender.connect([relay.url])
        let early = try event("sent before you looked")
        let first = await sender.publish(early)
        XCTAssertEqual(first, 1)
        let late = RelayPool()
        var got: [Online.Event] = []
        late.onEvent = { got.append($0) }
        late.connect([relay.url])
        late.subscribe(Online.filter(mailboxes: Online.mailboxes(for: keys, now: Date()), since: Date().addingTimeInterval(-3 * 86_400)))
        for _ in 0..<50 where got.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(got.first?.id, early.id)
        relay.rejectAll = true
        let refused = await sender.publish(try event("refused"))
        XCTAssertEqual(refused, 0)
        sender.disconnect(); late.disconnect()
    }

    func testUnreachableRelayCountsZeroQuickly() async throws {
        let pool = RelayPool()
        pool.connect([URL(string: "ws://127.0.0.1:1")!])
        let accepted = await pool.publish(try event("nobody home"), timeout: .seconds(2))
        XCTAssertEqual(accepted, 0)
        pool.disconnect()
    }
}
