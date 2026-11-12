import XCTest

/// Swiping left or right on the page moves between Send, Receive, Chat and Map, without taking over
/// the sideways drags that already mean something: swipe to reply on a chat bubble, and a text box.
/// Relays point at a dead local address, so nothing reaches the internet.
final class PageSwipeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1", "-no-tor"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat"].waitForExistence(timeout: 20))
        return app
    }

    /// The Map tab has a "Map" choice of its own below the slider, so the tab is the first match.
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement { app.buttons[name].firstMatch }

    private func expect(_ app: XCUIApplication, on name: String, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        let selected = NSPredicate(format: "isSelected == true")
        let waiter = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tab(app, name))], timeout: 5)
        XCTAssertEqual(waiter, .completed, "\(why): expected the \(name) tab", file: file, line: line)
    }

    /// A drag across the lower part of the page, clear of the text boxes at the top.
    private func swipe(_ app: XCUIApplication, toNext: Bool, y: CGFloat = 0.8) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: toNext ? 0.85 : 0.15, dy: y))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: toNext ? 0.15 : 0.85, dy: y))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    func testSwipingMovesThroughTheTabsAndStopsAtTheEnds() throws {
        let app = launch()
        expect(app, on: "Send", "at launch")
        swipe(app, toNext: true); expect(app, on: "Receive", "swipe left on Send")
        swipe(app, toNext: true); expect(app, on: "Chat", "swipe left on Receive")
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 5), "Chat opens on its drawer")
        swipe(app, toNext: true); expect(app, on: "Map", "swipe left on Chat")
        swipe(app, toNext: true); expect(app, on: "Map", "Map is the last tab")
        swipe(app, toNext: false); expect(app, on: "Chat", "swipe right on Map")
        swipe(app, toNext: false); expect(app, on: "Receive", "swipe right on Chat")
        swipe(app, toNext: false); expect(app, on: "Send", "swipe right on Receive")
        swipe(app, toNext: false); expect(app, on: "Send", "Send is the first tab")
        // Tapping still works.
        tab(app, "Chat").tap(); expect(app, on: "Chat", "tap")
    }

    /// A swipe that starts on a button changes tab and does not also press the button.
    func testSwipeAcrossAButtonDoesNotPressIt() throws {
        let app = launch()
        let button = app.buttons["copy-words"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: button.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        expect(app, on: "Receive", "swipe left across Encrypt Words")
        XCTAssertTrue(app.buttons["paste-decrypt"].waitForExistence(timeout: 5), "Receive is showing, with no sheet over it")
        XCTAssertTrue(tab(app, "Receive").isHittable, "no sheet opened")
    }

    /// Dragging inside a text box moves the cursor or selection there; it never changes tab.
    func testSwipeInATextBoxStaysOnTheTab() throws {
        let app = launch()
        let field = app.textFields["compose-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.swipeLeft()
        expect(app, on: "Send", "swipe left inside the message box")
    }

    /// In a conversation, swiping a bubble right replies and stays in Chat; swiping left goes to Map,
    /// and coming back finds the conversation still open.
    func testSwipeToReplyStillRepliesAndLeftGoesToMap() throws {
        let app = launch()
        tab(app, "Chat").tap()
        app.openDemoGroupFromDrawer()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("bring water")
        app.buttons["chat-send"].tap()
        let original = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: bring water.'")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))

        original.swipeRight()
        XCTAssertTrue(app.descendants(matching: .any)["chat-replying"].waitForExistence(timeout: 5), "the swipe replied")
        expect(app, on: "Chat", "swipe to reply")
        XCTAssertTrue(field.exists, "still in the conversation")
        app.buttons["chat-reply-cancel"].tap()

        original.swipeLeft()
        expect(app, on: "Map", "swipe left on a bubble")
        swipe(app, toNext: false)
        expect(app, on: "Chat", "swipe right on Map")
        XCTAssertTrue(app.textFields["chat-field"].waitForExistence(timeout: 5), "the conversation is still open")
    }
}
