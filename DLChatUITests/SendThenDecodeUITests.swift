import XCTest

/// Sends a message, reads the spoken words off the read-out screen, types them on Receive and
/// checks the English comes back. Uses the throwaway `-seed-demo` vault (one group, one draft).
final class SendThenDecodeUITests: XCTestCase {
    private let message = "need water at north gate"

    override func setUp() {
        continueAfterFailure = false
    }

    func testSendThenDecodeEndToEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"]
        app.launch()

        let show = app.buttons["Show the words"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        // The button enables once the seeded draft has loaded.
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: show)
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
            // The old group slides out while the new one slides in; read once only one is left.
            let one = NSPredicate(format: "count == 1")
            let settled = XCTNSPredicateExpectation(
                predicate: one, object: app.otherElements.matching(identifier: "readout-words"))
            XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed)
        }
        XCTAssertGreaterThanOrEqual(spoken.count, 11)
        app.buttons["Close"].tap()

        app.buttons["Receive"].tap()
        let byWord = app.buttons["decrypt-word-by-word"]
        XCTAssertTrue(byWord.waitForExistence(timeout: 10))
        byWord.tap()
        let field = app.textFields["word-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for word in spoken {
            field.typeText(word + "\n")
        }

        let decoded = app.staticTexts["decoded-text"]
        XCTAssertTrue(
            decoded.waitForExistence(timeout: 10),
            "spoken: \(spoken.count) words; on screen: \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(40))")
        XCTAssertEqual(decoded.label, message)
    }

    /// Encrypt Words shows Share in the group and Copy to clipboard; the words pasted at the top of Receive
    /// open with Decrypt, and Clear puts the page back to an empty paste field.
    func testEncryptWordsThenPasteDecryptAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"]
        app.launch()
        let encrypt = app.buttons["copy-words"]
        XCTAssertTrue(encrypt.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: encrypt)
        waitForExpectations(timeout: 10)
        encrypt.tap()

        let words = app.staticTexts["encrypted-words"]
        XCTAssertTrue(words.waitForExistence(timeout: 10))
        let sealed = words.label
        XCTAssertTrue(app.buttons["post-chat-send"].label.hasPrefix("Share in "), app.buttons["post-chat-send"].label)
        let copy = app.buttons["encrypted-words-copy"]
        XCTAssertTrue(copy.exists)
        XCTAssertEqual(copy.label, "Copy to clipboard", "nothing is copied until asked")
        copy.tap()
        XCTAssertEqual(copy.label, "Copied for 1 minute")
        app.buttons["encrypted-words-close"].tap()

        app.buttons["Receive"].tap()
        let paste = app.descendants(matching: .any)["paste-field"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["word-field"].exists, "the one-word field waits for Decrypt Word by Word")
        paste.tap()
        paste.typeText(sealed)
        app.buttons["paste-decrypt"].tap()
        let decoded = app.staticTexts["decoded-text"]
        XCTAssertTrue(decoded.waitForExistence(timeout: 10))
        XCTAssertEqual(decoded.label, message)
        XCTAssertFalse(paste.exists, "the message has the page to itself")

        let clear = app.buttons["receive-clear"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertFalse(decoded.exists)
        let first = String(sealed.split(separator: " ").first ?? "")
        XCTAssertFalse(((paste.value as? String) ?? "").contains(first), "the field is empty again")
    }

    /// Decrypt Word by Word: undoing back to no words stays on the word page; Clear goes back to paste.
    func testWordByWordUndoToNothingThenClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"]
        app.launch()
        app.buttons["Receive"].tap()
        let byWord = app.buttons["decrypt-word-by-word"]
        XCTAssertTrue(byWord.waitForExistence(timeout: 20))
        byWord.tap()
        let field = app.textFields["word-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("? ")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "still on the word page with no words")
        for _ in 0..<3 where !app.buttons["receive-clear"].isHittable { app.scrollViews.firstMatch.swipeUp() }
        app.buttons["receive-clear"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["paste-field"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }
}
