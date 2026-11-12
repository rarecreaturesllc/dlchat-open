import XCTest

/// First run: the PIN, then "Create a group for friends or family?". Create opens New group, "I have an
/// invite" opens Join, Skip opens the app with no group and is not asked again. `-no-demo-group` keeps the
/// throwaway `-seed-demo` vault empty, and `-fresh-lock` keeps the demo PIN out, as on a real first run.
final class FirstRunWelcomeUITests: XCTestCase {
    private let emptyNote = "Create or join a group first, in Chat."

    override func setUp() { continueAfterFailure = false }

    private func type(_ app: XCUIApplication, _ digits: String) {
        for digit in digits { app.buttons[String(digit)].tap() }
    }

    /// Launches on a fresh vault, makes the PIN 123456 and returns once the group question is showing.
    private func launchToWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-fresh-lock", "-no-demo-group"]
        app.launch()
        let create = app.buttons["lock-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["welcome-title"].isHittable, "the PIN comes first")
        type(app, "123456"); create.tap()
        type(app, "123456"); create.tap()
        // A simulator with Face ID enrolled asks about Face ID first: "Not now".
        let notNow = app.buttons["lock-biometrics-not-now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
        XCTAssertTrue(app.staticTexts["welcome-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcome-create"].isHittable)
        return app
    }

    func testSkipOpensTheAppWithNoGroupAndIsNotAskedAgain() throws {
        let app = launchToWelcome()
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["welcome-title"].exists)

        // The radio can still be turned on from Settings with no group.
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.switches["settings-radio"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // A cold start asks for the PIN, then opens the app: no question again.
        app.terminate()
        app.launchArguments = ["-seed-demo", "-fresh-lock", "-no-demo-group"]
        app.launch()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20))
        type(app, "123456"); unlock.tap()
        XCTAssertTrue(app.staticTexts[emptyNote].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["welcome-title"].waitForExistence(timeout: 2))
    }

    /// A friend installs DLChat and taps a contact invite link before making a PIN: after the PIN, Add a
    /// contact is showing on that invite, not the group question on top of it.
    func testContactLinkOnFirstRunOpensAddContactAfterThePIN() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-fresh-lock", "-no-demo-group", "-no-tor"]
        app.launch()
        let create = app.buttons["lock-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        app.open(URL(string: "dlchat://contact#AQAA" + String(repeating: "A", count: 40))!)
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        type(app, "123456"); create.tap()
        type(app, "123456"); create.tap()
        XCTAssertTrue(app.staticTexts["contact-from-link"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["contact-accept"].isHittable)
        XCTAssertFalse(app.staticTexts["welcome-title"].exists)
    }

    func testCreateOpensNewGroup() throws {
        let app = launchToWelcome()
        app.buttons["welcome-create"].tap()
        XCTAssertTrue(app.staticTexts["New group"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["welcome-title"].exists)
    }

    func testInviteOpensJoin() throws {
        let app = launchToWelcome()
        app.buttons["welcome-join"].tap()
        XCTAssertTrue(app.staticTexts["Join a group"].waitForExistence(timeout: 10))
    }
}
