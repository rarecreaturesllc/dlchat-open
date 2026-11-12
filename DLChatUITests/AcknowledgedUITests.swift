import XCTest

/// A message decrypted on Receive offers only Acknowledged. It posts "Decrypted" (never the words) in
/// Chat and opens Chat. Relays point at a dead local address, so nothing reaches the internet.
final class AcknowledgedUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openSeededMessage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1", "-no-tor"]
        app.launch()
        let show = app.buttons["Show the words"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: show)
        waitForExpectations(timeout: 10)
        show.tap()
        var spoken: [String] = []
        let words = app.otherElements["readout-words"]
        XCTAssertTrue(words.waitForExistence(timeout: 10))
        while true {
            spoken += words.label.split(separator: " ").map(String.init)
            let next = app.buttons["Next"]
            if !next.exists { break }
            next.tap()
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"),
                                                    object: app.otherElements.matching(identifier: "readout-words"))
            XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed)
        }
        app.buttons["Close"].tap()
        app.buttons["Receive"].tap()
        let byWord = app.buttons["decrypt-word-by-word"]
        XCTAssertTrue(byWord.waitForExistence(timeout: 10))
        byWord.tap()
        let field = app.textFields["word-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for word in spoken { field.typeText(word + "\n") }
        XCTAssertTrue(app.staticTexts["decoded-text"].waitForExistence(timeout: 10))
        // Put the keyboard away so the tab switch shows again.
        for _ in 0..<3 where !app.buttons["Chat"].isHittable { app.scrollViews.firstMatch.swipeDown() }
        return app
    }

    /// Chat asks once before going online; on, so the note can queue for a (dead) relay.
    private func turnOnlineOn(_ app: XCUIApplication) {
        app.buttons["Chat"].tap()
        app.openDemoGroupFromDrawer()
        let on = app.buttons["online-on"]
        XCTAssertTrue(on.waitForExistence(timeout: 10))
        on.tap()
        XCTAssertTrue(app.textFields["chat-field"].waitForExistence(timeout: 10))
    }

    func testAcknowledgedPostsOnlyDecryptedAndOpensChat() throws {
        let app = openSeededMessage()
        turnOnlineOn(app)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Received: need water'")).count, 0,
                       "decrypting alone puts nothing in Chat")
        app.buttons["Receive"].tap()
        XCTAssertTrue(app.staticTexts["decoded-text"].waitForExistence(timeout: 10), "the message is still open in Receive")
        XCTAssertFalse(app.buttons["copy-text"].exists)
        XCTAssertFalse(app.buttons["reply-got-it"].exists)
        let ack = app.buttons["acknowledge"]
        XCTAssertTrue(ack.waitForExistence(timeout: 10))
        for _ in 0..<3 where !ack.isHittable { app.swipeUp() }
        shot(app, "acknowledge-on")
        ack.tap()
        // Back in Chat, with the note and nothing of the message.
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: Decrypted.'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["chat-field"].exists, "Chat is showing")
        let leaked = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Received: need water'"))
        XCTAssertEqual(leaked.count, 0, "the decrypted message is not in Chat")
        shot(app, "acknowledge-chat")
    }

    /// Not acknowledged: nothing is posted, and the decrypted message does not show in Chat.
    func testWithoutAcknowledgingNothingIsPosted() throws {
        let app = openSeededMessage()
        turnOnlineOn(app)
        XCTAssertTrue(app.staticTexts["No messages yet. Say hello."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: Decrypted'")).count, 0)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
