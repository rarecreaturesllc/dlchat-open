import XCTest

/// The relay (and radio) status at the top of Chat is one short line, always folded when a chat opens;
/// tapping it opens the full detail over the messages without moving them. Relays point at a dead local address and Tor is off,
/// so the relay stays "connecting" and nothing reaches the internet.
final class ChatStatusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openChat() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1", "-no-tor"]
        app.launch()
        let chat = app.buttons["Chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        chat.tap()
        app.openDemoGroupFromDrawer()
        return app
    }

    func testStatusStartsFoldedAndTapOpensTheDetail() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let full = app.descendants(matching: .any)["online-status"].firstMatch
        let summary = app.buttons["chat-status-summary"]
        // One line from the start; the detail never opens by itself.
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "Relay connecting")
        XCTAssertFalse(full.exists)
        sleep(3)
        XCTAssertFalse(full.exists, "still folded")
        shot(app, "chat-status-folded")

        // Tap: the full detail shows and stays open.
        summary.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        XCTAssertTrue(full.label.contains("Relays · none reached yet"), full.label)
        XCTAssertFalse(summary.exists)
        sleep(3)
        XCTAssertTrue(full.exists, "Opened by hand, it stays open")
        shot(app, "chat-status-open")

        // Fold it again by hand.
        app.buttons["chat-status-fold"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(full.exists)

        // Leaving the chat and coming back: folded again.
        summary.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        app.buttons["chat-back"].tap()
        app.openDemoGroupFromDrawer()
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertFalse(full.exists, "a chat always opens with the status folded")
    }

    /// Opening or folding the status does not move the messages: one read mid-list stays where it was.
    func testOpeningTheStatusKeepsTheScrollPosition() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        for n in 1...14 {
            field.typeText("note \(n)")
            app.buttons["chat-send"].tap()
        }
        let scroll = app.scrollViews["chat-scroll"]
        // Close the keyboard and scroll up into the history.
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        scroll.swipeDown()
        let mid = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: note 6.'")).firstMatch
        XCTAssertTrue(mid.waitForExistence(timeout: 5))
        sleep(1)
        let before = mid.frame
        XCTAssertFalse(before.isEmpty)

        app.buttons["chat-status-summary"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["online-status"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(mid.frame.minY, before.minY, accuracy: 0.5, "opening the status moved the messages")
        shot(app, "chat-status-open-mid-list")

        app.buttons["chat-status-fold"].tap()
        XCTAssertTrue(app.buttons["chat-status-summary"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(mid.frame.minY, before.minY, accuracy: 0.5, "folding the status moved the messages")
    }

    /// Online chat off shows its own line and keeps the Turn on button reachable.
    func testFoldedLineKeepsTurnOnWhenOnlineIsOff() throws {
        let app = openChat()
        app.buttons["online-not-now"].tap()
        let summary = app.buttons["chat-status-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "Online chat is off")
        let turnOn = app.buttons["online-turn-on"]
        XCTAssertTrue(turnOn.isHittable)
        turnOn.tap()
        // Turning it on changes the line; the detail still waits for a tap.
        let connecting = NSPredicate(format: "label == 'Relay connecting'")
        expectation(for: connecting, evaluatedWith: summary)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.descendants(matching: .any)["online-status"].firstMatch.exists)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
