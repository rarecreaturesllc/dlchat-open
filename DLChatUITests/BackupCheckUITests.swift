import XCTest

/// Group details can check a written copy without showing the phrase.
final class BackupCheckUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openDetails(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"] + arguments
        app.launch()
        app.openManageGroups()
        app.buttons["details-Demo group"].tap()
        XCTAssertTrue(app.buttons["hold-reveal"].waitForExistence(timeout: 10))
        return app
    }

    func testCheckSaysWhatIsWrongWithoutShowingThePhrase() throws {
        let app = openDetails([])
        let open = app.buttons["open-backup-check"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        shot(app, "backup-check-on")
        open.tap()
        let field = app.textFields["backup-check-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("badge foam")
        app.buttons["backup-check"].tap()
        let result = app.descendants(matching: .any)["backup-check-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("Your copy has 2 words"), result.label)
        XCTAssertFalse(app.staticTexts["group-phrase"].exists)
        shot(app, "backup-check-result")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
