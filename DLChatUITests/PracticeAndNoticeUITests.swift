import XCTest

/// The practice drill from the Safety sheet, and the Meshtastic radio rules notice that must be
/// accepted before the radio can be turned on. Sound has no notice: DLChat is not for walkie-talkies.
/// Uses the throwaway `-seed-demo` vault; `-reset-demo` also clears the notice flag.
final class PracticeAndNoticeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"]
        app.launch()
        let show = app.buttons["Show the words"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: show)
        waitForExpectations(timeout: 10)
        return app
    }

    func testPracticeDrillCompletesWithoutRadio() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let open = app.buttons["practice-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        open.tap()

        let start = app.buttons["practice-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        var spoken: [String] = []
        let words = app.otherElements["practice-words"]
        XCTAssertTrue(words.waitForExistence(timeout: 20))
        while true {
            spoken += words.label.split(separator: " ").map(String.init)
            let next = app.buttons["practice-next"]
            if !next.exists { break }
            next.tap()
            let one = NSPredicate(format: "count == 1")
            let settled = XCTNSPredicateExpectation(
                predicate: one, object: app.otherElements.matching(identifier: "practice-words"))
            XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed)
        }
        XCTAssertGreaterThanOrEqual(spoken.count, 11)
        app.buttons["practice-listen"].tap()

        let field = app.textFields["practice-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for word in spoken { field.typeText(word + "\n") }

        let decoded = app.staticTexts["practice-decoded"]
        XCTAssertTrue(decoded.waitForExistence(timeout: 10))
        XCTAssertEqual(decoded.label, "meet at the bridge at noon")
    }

    /// Encrypt Sound opens straight away, with no radio notice in front of it.
    func testSoundOpensWithNoRadioNotice() throws {
        let app = launch()
        app.buttons["play-tones"].tap()
        XCTAssertTrue(app.buttons["tones-close"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["radio-notice-title"].exists)
        app.buttons["tones-close"].tap()
    }

    /// The radio switch starts off; turning it on shows the rules with "I accept", and Not now leaves it off.
    /// The rules stay readable from Settings. (Accepting is left to a device: it raises the Bluetooth prompt.)
    func testRadioNeedsTheRulesAcceptedAndNotNowLeavesItOff() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let radio = app.switches["settings-radio"]
        XCTAssertTrue(radio.waitForExistence(timeout: 10))
        for _ in 0..<6 where !radio.isHittable { app.swipeUp() }
        XCTAssertEqual(radio.value as? String, "0")
        radio.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["radio-notice-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["radio-notice-extra"].exists)
        XCTAssertTrue(app.buttons["radio-notice-continue"].exists)
        app.buttons["radio-notice-cancel"].tap()
        XCTAssertTrue(radio.waitForExistence(timeout: 10))
        XCTAssertEqual(radio.value as? String, "0")

        let rules = app.buttons["radio-rules-open"]
        for _ in 0..<6 where !rules.isHittable { app.swipeUp() }
        rules.tap()
        XCTAssertTrue(app.staticTexts["radio-notice-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["radio-notice-continue"].exists, "read-only from Settings")
    }

    func testSettingsShowsDocumentsAndRetention() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-retention"].waitForExistence(timeout: 10))
        let documents = app.buttons["settings-fold-documents"]
        for _ in 0..<6 where !documents.isHittable { app.swipeUp() }
        documents.tap()
        let terms = app.buttons["settings-doc-terms"]
        for _ in 0..<2 where !terms.isHittable { app.swipeUp() }
        terms.tap()
        XCTAssertTrue(app.staticTexts["Terms"].waitForExistence(timeout: 10))
    }
}
