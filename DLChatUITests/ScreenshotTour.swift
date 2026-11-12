import XCTest

/// One screenshot of every part of the app, attached to the test result. Not part of the normal
/// suite: run with TEST_RUNNER_DLCHAT_TOUR=1 xcodebuild test ... -only-testing:DLChatUITests/ScreenshotTour
/// Online chat points at a dead local relay and Tor is off, so nothing leaves the Simulator.
final class ScreenshotTour: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DLCHAT_TOUR"] == "1", "screenshot tour runs on request")
        continueAfterFailure = true
    }

    private var index = 0

    private func open(_ screen: String?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-no-tor", "-online-relays", "ws://127.0.0.1:1"]
            + (screen.map { ["-screen", $0] } ?? []) + extra
        app.launch()
        settle(2.5)
        return app
    }

    private func settle(_ seconds: TimeInterval) { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds) }

    private func shot(_ app: XCUIApplication, _ name: String) {
        index += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%02d-%@", index, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTour() throws {
        // Send, its three outputs, Receive and its two inputs.
        var app = open(nil); shot(app, "send")
        app = open("readout"); shot(app, "send-words")
        app = open("qr"); shot(app, "send-qr")
        app = open("tones"); shot(app, "send-tones")
        app = open("decode"); shot(app, "receive")
        app = open("scan"); shot(app, "receive-scan")
        app = open("listen"); shot(app, "receive-listen")
        app = open("meshmap"); shot(app, "mesh-map")

        // Chat: the ask-once card, then a sent message.
        app = open("chat"); shot(app, "chat-ask")
        if app.buttons["online-on"].waitForExistence(timeout: 5) {
            app.buttons["online-on"].tap()
            let field = app.textFields["chat-field"]
            if field.waitForExistence(timeout: 5) {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
                field.typeText("Meet at the north gate at 6")
                app.buttons["chat-send"].tap()
                settle(2)
                app.swipeDown()
                settle(1)
            }
            shot(app, "chat")
        }

        // Groups: the list, one group's details, New group, Join, and a picture invite.
        app = open("groups"); shot(app, "groups")
        if app.buttons["details-Demo group"].waitForExistence(timeout: 5) { app.buttons["details-Demo group"].tap(); settle(1.5); shot(app, "group-details") }
        app = open("create"); shot(app, "new-group")
        if app.buttons["Join"].waitForExistence(timeout: 5) { app.buttons["Join"].tap(); settle(1); shot(app, "join-group") }
        app = open("create")
        if app.buttons["share-picture"].waitForExistence(timeout: 20) {
            settle(1); shot(app, "picture-invite")
            let share = app.buttons["share-qr"]
            for _ in 0..<6 where !share.isHittable { app.swipeUp() }
            if share.exists { share.tap(); settle(1); shot(app, "new-group-phrase") }
        }

        // Settings, with Safety at the top.
        app = open("settings"); shot(app, "settings")
        for id in ["settings-online", "settings-radio"] {
            let toggle = app.switches[id]
            for _ in 0..<8 where !(toggle.exists && toggle.isHittable && toggle.frame.minY < app.frame.height * 0.35) { app.swipeUp(velocity: 600); settle(0.6) }
            shot(app, id == "settings-online" ? "settings-online-and-radio" : "settings-bottom")
        }
        app = open("practice"); shot(app, "practice-drill")
        app = open("radio"); shot(app, "radio-rules")
        app = open("notice"); shot(app, "radio-notice")
    }
}
