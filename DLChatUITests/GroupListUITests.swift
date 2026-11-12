import XCTest

/// Manage groups in the Chat drawer opens the group list: view a group's phrase behind a hold, then remove it.
/// Uses the throwaway `-seed-demo` vault (one group named "Demo group").
final class GroupListUITests: XCTestCase {
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

    func testManageGroupsOpensTheListAndPhraseNeedsAHold() throws {
        let app = launch()
        app.openManageGroups()
        XCTAssertTrue(app.buttons["choose-Demo group"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["choose-Demo group"].label, "Demo group, active group")
        app.buttons["details-Demo group"].tap()

        let reveal = app.buttons["hold-reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["group-phrase"].exists, "the phrase is hidden until held")
        reveal.press(forDuration: 1.0, thenDragTo: reveal)
        XCTAssertFalse(app.staticTexts["group-phrase"].exists, "letting go hides it again")
    }

    /// Meshtastic history: memory only by default; picking a period says it is kept and sealed;
    /// going back to "Until DLChat closes" asks first, since it erases what was kept.
    func testMeshtasticHistoryIsOptInAndShowsActivity() throws {
        let app = launch()
        app.openManageGroups()
        let history = app.buttons["mesh-history"]
        for _ in 0..<6 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertTrue(history.label.contains("until DLChat closes"), history.label)
        history.tap()
        XCTAssertTrue(app.staticTexts["mesh-activity-total"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mesh-activity-total"].label, "0 messages heard")
        let note = app.staticTexts["mesh-keep-note"]
        XCTAssertTrue(note.label.hasPrefix("Nothing is saved."), note.label)

        app.buttons["mesh-keep"].tap()
        app.buttons["7 days"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '0 messages kept'"), evaluatedWith: note)
        waitForExpectations(timeout: 10)

        app.buttons["mesh-keep"].tap()
        app.buttons["Until DLChat closes"].tap()
        XCTAssertTrue(app.buttons["Erase kept chats"].waitForExistence(timeout: 10))
        app.buttons["Erase kept chats"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Nothing is saved.'"), evaluatedWith: note)
        waitForExpectations(timeout: 10)
    }

    func testRemovingTheGroupErasesItAndSendIsDisabled() throws {
        let app = launch()
        app.openManageGroups()
        app.buttons["details-Demo group"].tap()

        let remove = app.buttons["remove-group"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        // Declining the confirmation keeps the group.
        // The system dialog has no Cancel button on this layout; a tap outside it dismisses it.
        XCTAssertTrue(app.buttons["Remove and erase"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Remove and erase"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(remove.exists)

        remove.tap()
        app.buttons["Remove and erase"].tap()
        XCTAssertTrue(app.staticTexts["No groups yet. Create one and share its words in person, or join with a phrase you were given."].waitForExistence(timeout: 10))
        app.buttons["groups-done"].tap()
        app.buttons["Send"].firstMatch.tap()  // Manage groups was opened from Chat; the note is on Send
        XCTAssertTrue(app.staticTexts["Create or join a group first, in Chat."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Show the words"].isEnabled)
    }

    /// An invite link opens Join with the phrase checked, shows the safety words, and joins on one tap.
    /// New group is already open, as on first run, so the link has to replace it.
    func testInviteLinkOpensJoinAndJoins() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "create"]
        app.launch()
        XCTAssertTrue(app.buttons["share-qr"].waitForExistence(timeout: 20))
        app.open(URL(string: "dlchat://join?name=Porch#badge-foam-chunk-kingdom-spoil-wages-denim-taxi-vixen-flag")!)

        XCTAssertTrue(app.staticTexts["This came from a link, which anyone can make. Join only if the person you expect reads you these same three safety words aloud."].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "invite-join"; shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Join group"].tap()
        // A joined group is added to the list; the active group stays as it was.
        app.openManageGroups()
        XCTAssertTrue(app.staticTexts["Porch"].waitForExistence(timeout: 10))
    }

    /// Create opens straight on the picture invite: the painted picture and a five-word password,
    /// ready to share, with no other tap first.
    func testCreateMakesAPictureInvite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "create", "-reveal-held"]
        app.launch()
        XCTAssertTrue(app.images["picture-invite"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["share-picture"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "picture-invite"; shot.lifetime = .keepAlways
        add(shot)
        let password = app.descendants(matching: .any)["picture-password"].firstMatch
        XCTAssertTrue(password.exists)
        XCTAssertEqual(password.label.split(separator: " ").count, 6, "\"Password:\" and five words")
        // The throwaway password, so the screenshot above can be opened by DLCore's screenshot check.
        let words = XCTAttachment(string: password.label); words.name = "picture-password"; words.lifetime = .keepAlways
        add(words)
        // Six words: a new password and a new picture.
        let six = app.buttons["6 words"]
        for _ in 0..<4 where !six.isHittable { app.swipeUp() }
        six.tap()
        expectation(for: NSPredicate(format: "label MATCHES %@", "Password:( [a-z]+){6}"), evaluatedWith: password)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.buttons["share-picture"].waitForExistence(timeout: 20))
    }

    /// A screenshot of the invite screen must not carry the password: the words wait behind a hold.
    func testPicturePasswordIsHiddenUntilHeld() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "create"]
        app.launch()
        XCTAssertTrue(app.images["picture-invite"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["hold-reveal"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["hold-reveal"].label, "Hold for your Picture Password")
        XCTAssertFalse(app.descendants(matching: .any)["picture-password"].exists, "hidden until held")
    }

    /// New group puts the picture walkthrough first and keeps the QR code and the full phrase behind
    /// Share group via QR. The 3 safety words are step 3, apart from the Picture Password.
    func testCreateKeepsQRBehindShareButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "create"]
        app.launch()
        XCTAssertTrue(app.images["picture-invite"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["phrase-qr"].exists, "QR waits behind Share group via QR")
        XCTAssertFalse(app.descendants(matching: .any)["phrase-words"].exists, "phrase waits behind Share group via QR")
        let safety = app.descendants(matching: .any)["safety-words"].firstMatch
        XCTAssertTrue(safety.exists)
        XCTAssertTrue(safety.label.hasPrefix("Safety words:"))
        let share = app.buttons["share-qr"]
        for _ in 0..<6 where !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(app.descendants(matching: .any)["phrase-qr"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["phrase-words"].firstMatch.exists)
        let qrShot = XCTAttachment(screenshot: app.screenshot()); qrShot.name = "share-group-qr"; qrShot.lifetime = .keepAlways
        add(qrShot)
        app.buttons["qr-done"].tap()
        XCTAssertTrue(app.buttons["share-qr"].waitForExistence(timeout: 10))
        // Closing before Save asks first: a friend may already be in the group.
        app.buttons["Close"].tap()
        let ask = app.sheets["Close without saving this group?"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        // Shown as a popover, the dialog drops its Keep going (cancel) button: a tap outside it keeps going.
        if app.buttons["Keep going"].exists { app.buttons["Keep going"].tap() } else { app.otherElements["PopoverDismissRegion"].tap() }
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share-qr"].exists)
    }

    /// Join, after a picture invite is opened: one numbered box per password word (5 by default, 6 on
    /// request), words in the wrong boxes do not open it, the right boxes do.
    func testPictureInvitePasswordGoesInNumberedBoxes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "create", "-demo-picture-invite"]
        app.launch()
        let first = app.textFields["picture-password-slot-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        for n in 1...5 { XCTAssertTrue(app.textFields["picture-password-slot-\(n)"].exists, "box \(n)") }
        XCTAssertFalse(app.textFields["picture-password-slot-6"].exists, "five boxes unless six are asked for")
        XCTAssertEqual(first.label, "Word 1 of 5")

        app.buttons["6 words"].tap()
        XCTAssertTrue(app.textFields["picture-password-slot-6"].waitForExistence(timeout: 5))
        app.buttons["5 words"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.textFields["picture-password-slot-6"])
        waitForExpectations(timeout: 5)

        func fill(_ words: [String]) {
            for (i, word) in words.enumerated() {
                let box = app.textFields["picture-password-slot-\(i + 1)"]
                box.tap()
                if let old = box.value as? String, !old.isEmpty, old != "Word \(i + 1)" {
                    box.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
                }
                box.typeText(word)
            }
        }
        let unlock = app.buttons["Unlock the picture"]
        // Words 1 and 2 swapped: the picture stays locked.
        fill(["river", "maple", "stone", "owl", "badge"])
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "picture-password-boxes"; shot.lifetime = .keepAlways
        add(shot)
        for _ in 0..<3 where !unlock.isHittable { app.swipeUp() }
        unlock.tap()
        let wrong = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "Those words do not open this picture")).firstMatch
        XCTAssertTrue(wrong.waitForExistence(timeout: 20))

        for _ in 0..<3 where !first.isHittable { app.swipeDown() }
        fill(["maple", "river", "stone", "owl", "badge"])
        for _ in 0..<3 where !unlock.isHittable { app.swipeUp() }
        unlock.tap()
        let accepted = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Picture unlocked")).firstMatch
        XCTAssertTrue(accepted.waitForExistence(timeout: 30))
    }
}

extension XCUIApplication {
    /// Opens the group list the only way there is: the Chat tab's drawer, then Manage groups.
    func openManageGroups(file: StaticString = #filePath, line: UInt = #line) {
        let manage = buttons["drawer-manage-groups"]
        XCTAssertTrue(buttons["Chat"].waitForExistence(timeout: 20), file: file, line: line)
        buttons["Chat"].tap()
        // A conversation already open on Chat: a second tap on the tab goes back to the drawer.
        if !manage.waitForExistence(timeout: 3) { buttons["Chat"].tap() }
        for _ in 0..<4 where !manage.isHittable { swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 10), file: file, line: line)
        manage.tap()
    }
}
