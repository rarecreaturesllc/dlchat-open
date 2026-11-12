import XCTest

/// "Read once" lives on Chat's eye button only: Receive keeps no words, so Send no longer needs the switch.
final class ReadOnceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 20))
        return app
    }

    func testReadOnceIsInChatNotSend() throws {
        let app = launch([])
        XCTAssertFalse(app.switches["read-once"].exists, "no Read once switch on Send")
        app.buttons["Chat"].tap()
        app.openDemoGroupFromDrawer()
        let on = app.buttons["online-on"]
        if on.waitForExistence(timeout: 10) { on.tap() }
        let eye = app.buttons["chat-read-once"]
        XCTAssertTrue(eye.waitForExistence(timeout: 10))
        XCTAssertEqual(eye.value as? String, "Off")
        eye.tap()
        XCTAssertEqual(eye.value as? String, "On")
        shot(app, "read-once-on")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
