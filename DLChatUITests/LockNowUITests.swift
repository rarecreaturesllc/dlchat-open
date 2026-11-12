import XCTest

/// The lock button locks the app at once; the PIN opens it again.
final class LockNowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 20))
        return app
    }

    /// The `-seed-demo` vault comes with the demo PIN 246810, since a PIN is always required.
    func testLockNowLocksAndPINUnlocks() throws {
        let app = launch([])
        let lockNow = app.buttons["lock-now"]
        XCTAssertTrue(lockNow.waitForExistence(timeout: 10), "always shown: there is always a PIN")
        shot(app, "lock-now-on")
        lockNow.tap()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        for digit in "246810" { app.buttons[String(digit)].tap() }
        unlock.tap()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
