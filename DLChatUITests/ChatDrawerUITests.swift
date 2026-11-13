import XCTest

extension XCUIApplication {
    /// The Chat tab opens on the drawer of all chats: pick the seeded demo group's chat.
    func openDemoGroupFromDrawer() {
        let row = buttons["drawer-group-Demo group"]
        // The drawer is a lazy List: at the largest text sizes the row exists only once scrolled on screen.
        for _ in 0..<4 where !row.waitForExistence(timeout: 10) { swipeUp() }
        XCTAssertTrue(row.exists, "the Chat drawer lists the demo group")
        row.tap()
    }
}

/// Chat opens on a drawer with four sections; Internet Messages can be set up from there and in Settings.
/// Nothing here reaches the internet: no relay is set, and Tor is off.
final class ChatDrawerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1", "-no-tor"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat"].waitForExistence(timeout: 20))
        return app
    }

    func testChatOpensOnTheDrawerWithFourSections() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["drawer-add-contact"].waitForExistence(timeout: 5))
        // The drawer is a lazy List: lower section headers exist only once scrolled on screen.
        for key in ["groups", "direct", "public", "nodes"] {
            let header = app.buttons["drawer-section-\(key)"]
            for _ in 0..<4 where !header.waitForExistence(timeout: 2) { app.swipeUp() }
            XCTAssertTrue(header.exists, "section \(key)")
        }
        for _ in 0..<4 where !app.buttons["drawer-group-Demo group"].isHittable { app.swipeDown() }
        // A group opens its chat; Chats goes back; Chat remembers the open chat across tabs.
        app.openDemoGroupFromDrawer()
        XCTAssertTrue(app.buttons["chat-back"].waitForExistence(timeout: 5))
        app.buttons["Send"].tap()
        app.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["chat-back"].waitForExistence(timeout: 5))
        app.buttons["chat-back"].tap()
        XCTAssertTrue(app.buttons["drawer-section-direct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["chat-drawer"].exists)
    }

    /// the owner's report: scroll the drawer, open a chat, tap Chats, and the drawer had jumped to the top.
    func testDrawerKeepsItsPlaceAfterAChat() throws {
        let app = XCUIApplication()
        // Large text, so the drawer is sure to be taller than the screen.
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1", "-no-tor",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat"].waitForExistence(timeout: 20))
        app.buttons["Chat"].tap()
        let header = app.buttons["drawer-section-groups"]
        let row = app.buttons["drawer-group-Demo group"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // Answer the group's one-time "Chat online?" question first, so the chat opened below is a plain chat.
        row.tap()
        XCTAssertTrue(app.buttons["online-not-now"].waitForExistence(timeout: 5))
        app.buttons["online-not-now"].tap()
        app.buttons["chat-back"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // Scroll a little at a time until the first header is off the top but the group's row still shows.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        for _ in 0..<20 where header.exists && header.isHittable {
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertFalse(header.exists && header.isHittable, "the drawer scrolled")
        XCTAssertTrue(row.isHittable, "the group's row is still on screen")
        let rowTop = row.frame.minY

        row.tap()
        XCTAssertTrue(app.buttons["chat-back"].waitForExistence(timeout: 5))
        // Not `exists`: the test tree still lists views that are hidden from VoiceOver.
        XCTAssertFalse(row.exists && row.isHittable, "the drawer can't be tapped under an open chat")
        app.buttons["chat-back"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(header.exists && header.isHittable, "the drawer did not jump back to the top")
        XCTAssertEqual(row.frame.minY, rowTop, accuracy: 2, "the drawer is where it was left")
    }

    func testSectionsCollapse() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        let header = app.buttons["drawer-section-groups"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].exists)
        header.tap()
        XCTAssertFalse(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 2))
        header.tap()
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 5))
    }

    /// Manage sits in the DL Group Chats header: it opens the group list, never folds the section, and is
    /// still there when the section is folded.
    func testManageInTheGroupsHeaderOpensTheGroupList() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        let manage = app.buttons["drawer-manage-groups"], header = app.buttons["drawer-section-groups"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertEqual(manage.label, "Manage groups")
        XCTAssertGreaterThanOrEqual(manage.frame.height, 44)
        manage.tap()
        XCTAssertTrue(app.buttons["choose-Demo group"].waitForExistence(timeout: 10), "the group list opened")
        app.buttons["groups-done"].tap()
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 5), "the section did not fold")

        header.tap()
        XCTAssertFalse(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 2))
        XCTAssertTrue(manage.isHittable, "Manage stays when the section is folded")
        manage.tap()
        XCTAssertTrue(app.buttons["choose-Demo group"].waitForExistence(timeout: 10))
        // The fold is remembered between launches: open the section again for the tests that follow.
        app.buttons["groups-done"].tap()
        header.tap()
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 5))
    }

    /// Every section has its own Manage key, shown even while the section is empty or folded; the two
    /// Meshtastic sections share one screen.
    func testEverySectionHasItsOwnManageKey() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        for (id, label) in [("drawer-manage-groups", "Manage groups"), ("drawer-manage-direct", "Manage Internet Messages"),
                            ("drawer-manage-public", "Manage Meshtastic"), ("drawer-manage-nodes", "Manage Meshtastic")] {
            let key = app.buttons[id]
            for _ in 0..<4 where !key.waitForExistence(timeout: 2) { app.swipeUp() }
            XCTAssertTrue(key.exists, id)
            XCTAssertEqual(key.label, label)
        }
        // No contacts yet, so Add stays in the section; a group exists, so its Add row is gone.
        XCTAssertFalse(app.buttons["drawer-new-group"].exists)
    }

    func testInternetManageHasAddContactAndRelays() throws {
        let app = launch()
        app.openManage("drawer-manage-direct")
        XCTAssertTrue(app.buttons["manage-add-contact"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["manage-relays"].exists)
        app.buttons["manage-add-contact"].tap()
        XCTAssertTrue(app.buttons["contact-make-invite"].waitForExistence(timeout: 5))
        app.buttons["add-contact-close"].tap()
        app.buttons["manage-relays"].tap()
        XCTAssertTrue(app.buttons["im-route-both"].waitForExistence(timeout: 5))
    }

    func testMeshManageOffersStatusAndHistoryAndKeepsTheRadioOff() throws {
        let app = launch()
        app.openManage("drawer-manage-nodes")
        XCTAssertTrue(app.staticTexts["mesh-manage-status"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mesh-manage-status"].label, "Radio off", "managing never turns the radio on")
        XCTAssertTrue(app.descendants(matching: .any)["mesh-history"].exists)
        let settings = app.descendants(matching: .any)["mesh-settings"]
        XCTAssertTrue(settings.exists, "the row is always listed, so it can be found")
        XCTAssertFalse(settings.isEnabled, "but only usable with a connected, confirmed radio")
    }

    /// A swipe right from the left edge of an open chat goes back to the Chats list; the same swipe from
    /// the middle of the screen does not (that is swipe to reply), and a short edge drag settles back.
    func testSwipeFromTheLeftEdgeGoesBackToChats() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        app.openDemoGroupFromDrawer()
        let back = app.buttons["chat-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let y = 0.55

        // From the middle: a page swipe to Receive (see PageSwipeUITests), not back. The chat is still open on return.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: y)))
        XCTAssertTrue(app.buttons["paste-decrypt"].waitForExistence(timeout: 5), "a swipe from the middle goes to Receive")
        app.buttons["Chat"].firstMatch.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 3), "a swipe from the middle does not go back")

        // A short drag from the edge settles back.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: y)).withOffset(CGVector(dx: 6, dy: 0))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(back.waitForExistence(timeout: 3), "a short drag settles back")
        XCTAssertTrue(back.isHittable)

        // A full drag from the edge goes back.
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y)))
        XCTAssertTrue(app.buttons["drawer-group-Demo group"].waitForExistence(timeout: 5), "back on the Chats list")
        XCTAssertFalse(back.exists)
    }

    func testAddContactShowsTheSteps() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        app.buttons["drawer-add-contact"].tap()
        XCTAssertTrue(app.buttons["contact-make-invite"].waitForExistence(timeout: 5))
        app.buttons["Use their invite"].tap()
        let paste = app.textViews["contact-paste"].exists ? app.textViews["contact-paste"] : app.textFields["contact-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        paste.typeText("not an invite")
        app.buttons["contact-accept"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["add-contact-problem"].waitForExistence(timeout: 5))
        app.buttons["add-contact-close"].tap()
        XCTAssertTrue(app.buttons["drawer-add-contact"].waitForExistence(timeout: 5))
    }

    /// A made-up short invite link (version byte 1, then 32 zero bytes). Nothing is fetched: Tor is off.
    private let contactLink = URL(string: "dlchat://contact#AQAA" + String(repeating: "A", count: 40))!

    /// A contact invite link opens Add a contact with one thing to do: Connect. When that fails (no Tor
    /// here), the scan and paste choices come back with the reason.
    func testContactLinkOpensReadyToConnect() throws {
        let app = launch()
        app.open(contactLink)
        XCTAssertTrue(app.staticTexts["contact-from-link"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["contact-scan"].exists)
        XCTAssertEqual(app.buttons["contact-accept"].label, "Connect")
        app.buttons["contact-accept"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["add-contact-problem"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["contact-scan"].waitForExistence(timeout: 5))
    }

    /// The link arrives while Add a contact is already open (they opened it, then tapped the link in
    /// Messages). It used to be dropped, leaving the screen on "Show my invite".
    func testContactLinkWhileAddContactIsOpenIsKept() throws {
        let app = launch()
        app.buttons["Chat"].tap()
        app.buttons["drawer-add-contact"].tap()
        XCTAssertTrue(app.buttons["contact-make-invite"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(contactLink) // not app.open: that relaunches the app, and this is about a link reaching the running one
        XCTAssertTrue(app.staticTexts["contact-from-link"].waitForExistence(timeout: 15))
        // Closing it and adding a contact from the drawer starts clean, not on the old link.
        app.buttons["add-contact-close"].tap()
        app.buttons["drawer-add-contact"].tap()
        XCTAssertTrue(app.buttons["contact-make-invite"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["contact-from-link"].exists)
    }

    func testSettingsOffersPrivatePublicOrBoth() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let row = app.buttons["settings-internet-messaging"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        for id in ["im-route-privateRelays", "im-route-publicRelays", "im-route-both"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id)
        }
        // Public relays are the default until DLChat has a private relay running.
        XCTAssertTrue(app.buttons["im-route-publicRelays"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["im-private-unavailable"].exists)
        // Picking private relays with none set up says that messages come by public relays meanwhile.
        app.buttons["im-route-privateRelays"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["im-private-unavailable"].waitForExistence(timeout: 5))
        app.buttons["im-route-both"].tap()
        XCTAssertTrue(app.buttons["im-route-both"].isSelected)
    }
}
