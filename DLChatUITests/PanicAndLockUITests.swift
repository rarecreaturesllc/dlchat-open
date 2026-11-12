import XCTest

/// Panic wipe by holding the button, and the duress PIN through a real background and return.
/// Both use the throwaway `-seed-demo` vault (one group, one draft).
final class PanicAndLockUITests: XCTestCase {
    private let emptyNote = "Create or join a group first, in Chat."

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

    /// Safety sits at the top of Settings.
    private func openSafety(_ app: XCUIApplication) {
        let button = app.buttons["settings-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    func testHoldingTheWipeButtonErasesTheGroup() throws {
        let app = launch()
        XCTAssertFalse(app.staticTexts[emptyNote].exists)
        openSafety(app)

        let wipe = app.buttons["Wipe everything"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 10))
        // A quick tap does nothing.
        wipe.tap()
        XCTAssertTrue(wipe.exists)
        wipe.press(forDuration: 3.6)

        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Show the words"].isEnabled)
    }

    func testDuressPINWipesAndOpensAnEmptyApp() throws {
        let app = launch()
        setDuressPIN(app, "999999")

        // Leaving the app locks it.
        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))

        // A wrong PIN says so and keeps the app locked.
        for digit in "000000" { app.buttons[String(digit)].tap() }
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Wrong PIN."].waitForExistence(timeout: 5))

        for digit in "999999" { app.buttons[String(digit)].tap() }
        unlock.tap()

        // It unlocks as normal, with nothing in it.
        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertFalse(unlock.exists)
        XCTAssertFalse(app.buttons["lock-create"].exists, "no new-PIN screen gives the duress unlock away")

        // The next time the app is opened, a new PIN is required.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["lock-create"].waitForExistence(timeout: 10))
    }

    /// The lock now sits above open screens, so a duress PIN must also clear what was left open behind it.
    func testDuressPINClosesAScreenLeftOpenBehindTheLock() throws {
        let app = launch()
        setDuressPIN(app, "999999")

        app.buttons["Show the words"].tap()
        XCTAssertTrue(app.otherElements["readout-words"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        for digit in "999999" { app.buttons[String(digit)].tap() }
        unlock.tap()

        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.otherElements["readout-words"].exists)
    }

    /// Sets a duress PIN through Safety (the `-seed-demo` vault already has the PIN 246810) and leaves the app on the main screen.
    private func setDuressPIN(_ app: XCUIApplication, _ value: String) {
        openSafety(app)
        let fold = app.buttons["safety-fold-duress"]
        XCTAssertTrue(fold.waitForExistence(timeout: 10))
        fold.tap()
        let duress = app.secureTextFields["safety-Duress PIN"]
        XCTAssertTrue(duress.waitForExistence(timeout: 10))
        duress.tap()
        duress.typeText(value)
        app.staticTexts["safety-duress-about"].tap()
        app.buttons["Set duress PIN"].tap()
        XCTAssertTrue(app.staticTexts["Duress PIN saved."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testLockShowsAboveAnOpenSheet() throws {
        let app = launch()
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let retention = app.otherElements["settings-retention"]
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertTrue(unlock.isHittable)
        XCTAssertFalse(app.buttons["Done"].isHittable)
        XCTAssertFalse(retention.isHittable)
    }

    func testHoldToWipeIsOnTheLockScreen() throws {
        let app = launch()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["lock-unlock"].waitForExistence(timeout: 10))
        let wipe = app.buttons["Wipe everything"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 5))
        wipe.press(forDuration: 3.6)

        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["lock-unlock"].exists)
    }
}
