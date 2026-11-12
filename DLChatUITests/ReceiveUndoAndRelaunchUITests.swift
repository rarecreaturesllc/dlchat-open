import XCTest

/// Receive: Undo down to no words must not crash. And the owner's rule: if the app is killed or crashes,
/// nothing from Send or Receive is there when it opens again (Chat may keep its messages).
final class ReceiveUndoAndRelaunchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo"] + (reset ? ["-reset-demo"] : [])
        app.launch()
        return app
    }

    private func openReceive(_ app: XCUIApplication) {
        let receive = app.buttons["Receive"]
        XCTAssertTrue(receive.waitForExistence(timeout: 20))
        receive.tap()
        // Receive opens paste-first (Send/Receive layout); typed words are one tap away.
        XCTAssertTrue(app.descendants(matching: .any)["paste-field"].waitForExistence(timeout: 10), "Receive opens empty, paste-first")
        let byWord = app.buttons["decrypt-word-by-word"]
        XCTAssertTrue(byWord.waitForExistence(timeout: 5))
        byWord.tap()
        XCTAssertTrue(app.textFields["word-field"].waitForExistence(timeout: 10))
    }

    /// Build 15 crashed when Undo removed the last word.
    func testUndoToZeroWordsDoesNotCrash() throws {
        let app = launch(reset: true)
        openReceive(app)
        let missed = app.buttons["Missed a word"]
        for _ in 0..<3 { missed.tap() }
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 { undo.tap() }
        // Back to no words: the word box is still there and the app is still running.
        XCTAssertTrue(app.textFields["word-field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(undo.isEnabled)
        // And Receive still works after it.
        missed.tap()
        XCTAssertTrue(undo.isEnabled)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Text typed in Send and words entered in Receive are gone after the app is killed and opened again.
    func testKilledAppOpensWithEmptySendAndReceive() throws {
        let app = launch(reset: true)
        let field = app.descendants(matching: .any)["compose-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        // The seeded draft is there in this run.
        XCTAssertEqual(field.value as? String, "need water at north gate")
        openReceive(app)
        let missed = app.buttons["Missed a word"]
        for _ in 0..<2 { missed.tap() }
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled, "words entered")

        // Killed with no chance to clean up (like a crash), then opened again on the same vault.
        app.terminate()
        let again = launch(reset: false)
        let unlock = again.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20))
        for digit in "246810" { again.buttons[String(digit)].tap() }
        unlock.tap()

        let compose = again.descendants(matching: .any)["compose-field"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        // Empty: the new Send box reports "" when empty, the old one reported its placeholder.
        let sendText = compose.value as? String ?? ""
        XCTAssertTrue(sendText.isEmpty || sendText == "Type your message", "Send is empty, found: \(sendText)")
        // Receive has no words: it opens paste-first (only shown when no words are entered),
        // and word by word starts empty.
        openReceive(again)
        XCTAssertFalse(again.buttons["Undo"].firstMatch.isEnabled)
    }
}
