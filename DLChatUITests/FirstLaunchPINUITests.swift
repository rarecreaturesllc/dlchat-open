import XCTest

/// The PIN is required. With no PIN yet (first launch, or an install from before it was required) the app
/// asks for one before anything else, it cannot be skipped, and from then on every open asks for it.
/// `-fresh-lock` keeps the demo PIN out of the throwaway `-seed-demo` vault.
final class FirstLaunchPINUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func type(_ app: XCUIApplication, _ digits: String) {
        for digit in digits { app.buttons[String(digit)].tap() }
    }

    /// On a simulator with Face ID enrolled the new PIN is followed by the Face ID question: answer "Not now".
    private func declineFaceIDIfOffered(_ app: XCUIApplication) {
        let notNow = app.buttons["lock-biometrics-not-now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
    }

    func testNoPINMeansCreateOneFirstAndThenEveryOpenAsks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-fresh-lock"]
        app.launch()

        let create = app.buttons["lock-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        XCTAssertTrue(create.isHittable)
        XCTAssertFalse(app.buttons["Show the words"].isHittable, "nothing behind it can be used")

        // Leaving and coming back does not skip it.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(create.waitForExistence(timeout: 10))

        // Too short: Next stays off.
        type(app, "1234")
        XCTAssertFalse(create.isEnabled)
        type(app, "56")
        create.tap()
        // A different second entry starts again.
        type(app, "123457")
        create.tap()
        XCTAssertTrue(app.staticTexts["Those did not match. Start again."].waitForExistence(timeout: 5))

        type(app, "123456")
        create.tap()
        type(app, "123456")
        create.tap()
        declineFaceIDIfOffered(app)
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))
        XCTAssertFalse(create.exists)

        // Every return from the background asks for it.
        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        type(app, "123456")
        unlock.tap()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))

        // And so does a cold start (same vault, no reset).
        app.terminate()
        app.launchArguments = ["-seed-demo", "-fresh-lock"]
        app.launch()
        XCTAssertTrue(app.buttons["lock-unlock"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["lock-create"].exists)
    }

    func testFourAndEightDigitPINsCanBeChosen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-fresh-lock"]
        app.launch()
        let create = app.buttons["lock-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))

        // 8 digits: 6 is not enough, and a ninth digit is ignored.
        app.buttons["8 digits"].tap()
        type(app, "135790")
        XCTAssertFalse(create.isEnabled)
        type(app, "247")
        create.tap()
        type(app, "13579024")
        create.tap()
        declineFaceIDIfOffered(app)
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))

        // Wipe from Settings > Safety, then the next open asks for a new PIN: pick 4 digits.
        app.buttons["settings-button"].tap()
        let wipe = app.buttons["Wipe everything"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 10))
        wipe.press(forDuration: 3.6)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        app.buttons["4 digits"].tap()
        type(app, "1357")
        create.tap()
        type(app, "1357")
        create.tap()
        declineFaceIDIfOffered(app)
        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        type(app, "1357")
        unlock.tap()
        XCTAssertFalse(unlock.waitForExistence(timeout: 2))
    }

    /// Right after the PIN is typed twice, a phone with Face ID set up is asked once whether to unlock with it.
    /// "Not now" opens DLChat with Face ID off. Needs a simulator with Face ID enrolled (Features > Face ID >
    /// Enrolled, or `notifyutil -s com.apple.BiometricKit.enrollmentChanged 1` then `-p` it); skipped otherwise.
    func testFaceIDIsOfferedOnceRightAfterThePIN() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-fresh-lock"]
        app.launch()
        let create = app.buttons["lock-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        type(app, "123456")
        create.tap()
        type(app, "123456")
        create.tap()
        let offer = app.staticTexts["lock-biometrics-offer"]
        try XCTSkipUnless(offer.waitForExistence(timeout: 5), "this simulator has no Face ID enrolled")
        XCTAssertFalse(app.buttons["Show the words"].isHittable, "nothing opens until the question is answered")
        XCTAssertTrue(app.buttons["lock-biometrics-yes"].exists)
        app.buttons["lock-biometrics-not-now"].tap()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))
        XCTAssertFalse(offer.exists)

        // Not asked again: the next open goes straight to the PIN pad.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["lock-unlock"].waitForExistence(timeout: 10))
        XCTAssertFalse(offer.exists)
    }

    /// Locked with Face ID on: a plain cover shows, never the PIN pad, until Face ID says no or "Use PIN" is
    /// tapped; the PIN then opens DLChat as always. `-hold-faceid` keeps Face ID from answering (the Simulator
    /// answers at once). Needs a simulator with Face ID enrolled; skipped otherwise.
    func testFaceIDCoverHidesThePadAndUsePINBringsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-demo-faceid", "-hold-faceid"]
        app.launch()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        app.activate()
        let usePIN = app.buttons["lock-use-pin"]
        try XCTSkipUnless(usePIN.waitForExistence(timeout: 5), "this simulator has no Face ID enrolled")
        XCTAssertFalse(app.buttons["lock-unlock"].exists, "no PIN pad while Face ID decides")
        XCTAssertFalse(app.buttons["1"].exists)
        XCTAssertFalse(app.buttons["Show the words"].isHittable, "nothing behind the cover can be used")

        usePIN.tap()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "Use PIN brings the pad")
        XCTAssertTrue(app.buttons["Wipe everything"].exists, "and the wipe with it")
        type(app, "246810")
        unlock.tap()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))
        XCTAssertFalse(unlock.exists)
    }
}
