import CryptoKit
import P256K
import XCTest
@testable import DLCore

final class OnlineTests: XCTestCase {
    private let keys = Keys(masterData: Data(repeating: 7, count: 32))
    private let other = Keys(masterData: Data(repeating: 9, count: 32))
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private func wire(_ text: String, _ keys: Keys) throws -> Data {
        NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys), ttl: 0)
    }

    func testRoundTripOnlyForTheGroup() throws {
        let original = try wire("meet at the bridge", keys)
        let event = try Online.event(wire: original, keys: keys, now: now)
        XCTAssertTrue(event.isValid)
        XCTAssertEqual(event.kind, 1059)
        XCTAssertEqual(event.tags.first, ["p", Online.mailbox(for: keys, on: now)])
        let opened = try XCTUnwrap(Online.wire(from: event, trying: [other, keys]))
        XCTAssertEqual(opened.wire, original)
        XCTAssertEqual(opened.keysIndex, 1)
        XCTAssertNil(Online.wire(from: event, trying: [other]))
        // The opened wire reads with the normal Nearby path.
        XCTAssertEqual(Receiver.readNearby(wire: opened.wire, trying: [keys])?.text, "meet at the bridge")
    }

    func testTamperingBreaksTheEvent() throws {
        let event = try Online.event(wire: try wire("hello", keys), keys: keys, now: now)
        var changed = Online.Event(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt + 1, kind: event.kind,
                                   tags: event.tags, content: event.content, sig: event.sig)
        XCTAssertFalse(changed.isValid)
        changed = Online.Event(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt, kind: event.kind,
                               tags: event.tags, content: event.content, sig: String(repeating: "0", count: 128))
        XCTAssertFalse(changed.isValid)
        XCTAssertNil(Online.wire(from: changed, trying: [keys]))
    }

    func testEachPostHasItsOwnAuthorAndABlurredTime() throws {
        let a = try Online.event(wire: try wire("hello", keys), keys: keys, now: now)
        let b = try Online.event(wire: try wire("hello", keys), keys: keys, now: now)
        XCTAssertNotEqual(a.pubkey, b.pubkey)
        for e in [a, b] {
            XCTAssertLessThanOrEqual(e.createdAt, Int(now.timeIntervalSince1970))
            XCTAssertGreaterThanOrEqual(e.createdAt, Int(now.timeIntervalSince1970) - 2 * 86_400)
            // Expiry follows the blurred time, so it cannot reveal the real one, yet keeps 14 days at least.
            let expiry = try XCTUnwrap(e.tags.last.flatMap { $0.first == "expiration" ? Int($0[1]) : nil })
            XCTAssertEqual(expiry, e.createdAt + 16 * 86_400)
            XCTAssertGreaterThanOrEqual(expiry, Int(now.timeIntervalSince1970) + 14 * 86_400)
        }
    }

    func testMailboxRotatesDailyAndDiffersByGroup() {
        let today = Online.mailbox(for: keys, on: now)
        XCTAssertEqual(today.count, 64)
        XCTAssertEqual(today, Online.mailbox(for: keys, on: now.addingTimeInterval(60)))
        XCTAssertNotEqual(today, Online.mailbox(for: keys, on: now.addingTimeInterval(86_400)))
        XCTAssertNotEqual(today, Online.mailbox(for: other, on: now))
        // Rooms share the group's mailbox.
        XCTAssertEqual(today, Online.mailbox(for: Keys(masterData: Data(repeating: 7, count: 32), room: "porch"), on: now))
        let watched = Online.mailboxes(for: keys, now: now)
        XCTAssertEqual(watched.count, 16)
        XCTAssertTrue(watched.contains(today))
    }

    func testLengthOnlyShowsABucket() throws {
        let short = try Online.event(wire: try wire("ok", keys), keys: keys, now: now)
        let longer = try Online.event(wire: try wire("need water and fuel at the north gate by noon", keys), keys: keys, now: now)
        XCTAssertEqual(short.content.count, longer.content.count)
    }

    func testJSONRoundTripAndEscaping() throws {
        let event = try Online.event(wire: try wire("hello", keys), keys: keys, now: now)
        let data = try JSONSerialization.data(withJSONObject: event.json)
        let back = try XCTUnwrap(Online.Event(json: try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])))
        XCTAssertEqual(back, event)
        XCTAssertTrue(back.isValid)
        XCTAssertEqual(quote("a\"b\\c\nd\te\u{08}f\u{0C}g\rh é"), "\"a\\\"b\\\\c\\nd\\te\\bf\\fg\\rh é\"")
    }

    func testAuthEventsSignInAsEachMailbox() throws {
        let relay = URL(string: "wss://relay.example")!
        let events = try Online.authEvents(challenge: "abc", relay: relay, keys: [keys], now: now, days: 3)
        XCTAssertEqual(events.count, 4)  // tomorrow + 3 days
        XCTAssertTrue(events.allSatisfy { $0.kind == 22242 && $0.isValid && $0.tags == [["relay", "wss://relay.example"], ["challenge", "abc"]] })
        XCTAssertEqual(Set(events.map(\.pubkey)), Set(Online.mailboxes(for: keys, now: now, days: 3)))
    }

    /// BIP-340 test vector 0, so our signatures are the ones every Nostr relay and client checks.
    func testBIP340Vector() throws {
        let secret = [UInt8](repeating: 0, count: 31) + [3]
        let key = try P256K.Schnorr.PrivateKey(dataRepresentation: secret)
        XCTAssertEqual(hex(key.xonly.bytes), "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")
        var message = [UInt8](repeating: 0, count: 32)
        var aux = [UInt8](repeating: 0, count: 32)
        let signature = try key.signature(message: &message, auxiliaryRand: &aux, strict: true)
        XCTAssertEqual(hex(Array(signature.dataRepresentation)),
                       "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1cE2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0".lowercased())
    }
}
