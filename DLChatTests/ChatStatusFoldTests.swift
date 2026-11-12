import XCTest
@testable import DLChat

/// The folded Chat status line: what it says, and that a problem never folds away.
final class ChatStatusFoldTests: XCTestCase {
    private func radio(_ status: MeshtasticModel.Status, isMine: Bool = true, problem: String? = nil, licensed: Bool = false,
                       applying: Bool = false, regionUnset: Bool = false, letGoByHand: Bool = false) -> ChatStatusFold.Part? {
        ChatStatusFold.radio(isOn: true, problem: problem, licensed: licensed, applying: applying, regionUnset: regionUnset,
                             status: status, isMine: isMine, letGoByHand: letGoByHand)
    }

    func testSummaryWording() {
        XCTAssertEqual(ChatStatusFold(relays: .active, radio: .active).summary, "Relay and radio active")
        XCTAssertEqual(ChatStatusFold(relays: .active, radio: nil).summary, "Relay active")
        XCTAssertEqual(ChatStatusFold(relays: .off, radio: .active).summary, "Radio active · online chat is off")
        XCTAssertEqual(ChatStatusFold(relays: .connecting, radio: .active).summary, "Radio active · relay connecting")
        XCTAssertEqual(ChatStatusFold(relays: .connecting, radio: .connecting).summary, "Relay and radio connecting")
        XCTAssertEqual(ChatStatusFold(relays: .off, radio: nil).summary, "Online chat is off")
    }

    func testRelayParts() {
        XCTAssertEqual(ChatStatusFold.relays(isOn: false, torOn: true, torReady: false, torFailed: false, connected: 0), .off)
        XCTAssertEqual(ChatStatusFold.relays(isOn: true, torOn: true, torReady: false, torFailed: false, connected: 0), .connecting)
        XCTAssertEqual(ChatStatusFold.relays(isOn: true, torOn: true, torReady: false, torFailed: true, connected: 0), .attention)
        XCTAssertEqual(ChatStatusFold.relays(isOn: true, torOn: true, torReady: true, torFailed: false, connected: 0), .connecting)
        XCTAssertEqual(ChatStatusFold.relays(isOn: true, torOn: true, torReady: true, torFailed: false, connected: 2), .active)
        XCTAssertEqual(ChatStatusFold.relays(isOn: true, torOn: false, torReady: false, torFailed: false, connected: 1), .active)
    }

    func testRadioParts() {
        XCTAssertNil(ChatStatusFold.radio(isOn: false, problem: nil, licensed: false, applying: false, regionUnset: false,
                                          status: .ready, isMine: true, letGoByHand: false))
        XCTAssertEqual(radio(.ready), .active)
        XCTAssertEqual(radio(.searching), .connecting)
        XCTAssertEqual(radio(.connecting), .connecting)
        XCTAssertEqual(radio(.ready, applying: true), .connecting)
        XCTAssertEqual(radio(.released), .connecting)
        // Anything that needs the person stays visible.
        XCTAssertEqual(radio(.ready, isMine: false), .attention)
        XCTAssertEqual(radio(.ready, regionUnset: true), .attention)
        XCTAssertEqual(radio(.ready, licensed: true), .attention)
        XCTAssertEqual(radio(.ready, problem: "Could not send"), .attention)
        XCTAssertEqual(radio(.released, letGoByHand: true), .attention)
        for status: MeshtasticModel.Status in [.bluetoothOff, .unauthorized, .disconnected, .busy] {
            XCTAssertEqual(radio(status), .attention, "\(status)")
        }
    }

    func testProblemsNeverFold() {
        XCTAssertTrue(ChatStatusFold(relays: .attention, radio: .active).needsAttention)
        XCTAssertTrue(ChatStatusFold(relays: .active, radio: .attention).needsAttention)
        XCTAssertFalse(ChatStatusFold(relays: .off, radio: .connecting).needsAttention)
        XCTAssertFalse(ChatStatusFold(relays: .active, radio: nil).needsAttention)
    }
}
