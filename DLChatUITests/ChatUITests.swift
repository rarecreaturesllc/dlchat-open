import XCTest

/// The Chat tab asks once before going online, then shows sent messages with their state.
/// Relays point at a dead local address, so nothing reaches the internet.
final class ChatUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openChat(tor: Bool = false, largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-online-relays", "ws://127.0.0.1:1"] + (tor ? [] : ["-no-tor"])
            + (largestText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        let chat = app.buttons["Chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        chat.tap()
        app.openDemoGroupFromDrawer()
        return app
    }

    func testAskOnceThenSendQueuesWithoutARelay() throws {
        let app = openChat()
        let on = app.buttons["online-on"]
        XCTAssertTrue(on.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Chat online?"].exists)
        shot(app, "chat-ask")
        on.tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // The seeded draft is the same text box; replace it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()  // cursor at the end
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("hello porch")
        app.buttons["chat-send"].tap()
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: hello porch.'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let waiting = NSPredicate(format: "label CONTAINS 'waiting for a connection'")
        expectation(for: waiting, evaluatedWith: bubble)
        waitForExpectations(timeout: 15)
        shot(app, "chat-sent")
    }

    /// Once a message is sent, the box empties for the next one, with the keyboard still up,
    /// and stays empty (the draft autosave must not bring the sent text back).
    func testSendEmptiesTheMessageBox() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("box should empty")
        app.buttons["chat-send"].tap()
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: box should empty.'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let empty = NSPredicate(format: "NOT (value CONTAINS 'box should empty')")
        expectation(for: empty, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        sleep(1)  // past the draft autosave
        XCTAssertFalse((field.value as? String ?? "").contains("box should empty"), "still in the box: \(field.value ?? "")")
        XCTAssertFalse(app.buttons["chat-send"].isEnabled, "Send is off once the box is empty")
        // The keyboard stays up, and the next message types into an empty box.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays up after Send")
        field.typeText("next one")
        XCTAssertEqual(field.value as? String, "next one")
    }

    /// The ^ menu says what is connected and lets the person choose; with nothing chosen, nothing is sent.
    func testSendByMenuShowsWhatIsConnectedAndCanTurnRelaysOff() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let route = app.buttons["chat-route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let summary = app.staticTexts["route-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("No relays connected yet"), summary.label)
        XCTAssertTrue(summary.label.contains("the radio is off"), summary.label)
        try app.performAccessibilityAudit { $0.auditType == .dynamicType && $0.element?.elementType == .staticText }
        let relays = app.switches["route-relays"]
        relays.switches.firstMatch.tap()
        XCTAssertEqual(relays.value as? String, "0")
        app.buttons["Done"].tap()
        let field = app.textFields["chat-field"]
        field.tap()
        field.typeText(" test")
        app.buttons["chat-send"].tap()
        let problem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Nothing is chosen'")).firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
    }

    /// At the largest text size the ask-once card scrolls inside its space, so the bars above stay
    /// in reach and both buttons can be scrolled to.
    func testAskOnceScrollsAtLargestTextSize() throws {
        let app = openChat(largestText: true)
        XCTAssertTrue(app.staticTexts["Chat online?"].waitForExistence(timeout: 10))
        for tab in ["Chat", "Receive"] {
            XCTAssertTrue(app.buttons[tab].isHittable, "\(tab) tab is out of reach")
        }
        XCTAssertTrue(app.buttons["chat-back"].isHittable, "the Chats back button is out of reach")
        let notNow = app.buttons["online-not-now"]
        // Swipes on the card itself (the bars above are tall at this size), slowly: a tap during a fling only stops it.
        let card = app.scrollViews["chat-ask-scroll"]
        for _ in 0..<12 where !notNow.isHittable { card.swipeUp(velocity: .slow) }
        XCTAssertTrue(notNow.isHittable, "Not now can't be scrolled to")
        XCTAssertTrue(app.buttons["chat-back"].isHittable)
        notNow.tap()
        XCTAssertTrue(app.buttons["chat-status-summary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Chat online?"].exists)
    }

    func testNotNowKeepsItOffAndSettingsCanTurnItOn() throws {
        let app = openChat()
        app.buttons["online-not-now"].tap()
        // The status lines fold after a moment into one line (ChatStatusUITests covers the folding).
        let status = app.buttons["chat-status-summary"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Online chat is off"), status.label)
        app.buttons["settings-button"].tap()
        let toggle = app.switches["settings-online"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        // Safety comes first in Settings, so the connection switches are further down.
        // Slow swipes until the whole switch is inside the scroll view: a tap during a fling only stops the scroll.
        let scroll = app.scrollViews["settings-scroll"]
        for _ in 0..<8 where !scroll.frame.contains(toggle.frame) { scroll.swipeUp(velocity: .slow) }
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        // The relay list sits in the folded "Relays" row.
        app.buttons["settings-fold-relays"].tap()
        XCTAssertTrue(app.staticTexts["ws://127.0.0.1:1"].waitForExistence(timeout: 5))
        shot(app, "settings-online")
    }

    /// Tor is on by default and shows its state; turning it off hides the status. The relay is a dead
    /// local address, so whether Tor connects, is still connecting, or fails offline, no message goes anywhere.
    func testTorIsOnByDefaultAndCanBeTurnedOff() throws {
        let app = openChat(tor: true)
        app.buttons["online-on"].tap()
        app.buttons["settings-button"].tap()
        let tor = app.switches["settings-tor"]
        XCTAssertTrue(tor.waitForExistence(timeout: 10))
        for _ in 0..<6 where !tor.isHittable { app.swipeUp() }
        XCTAssertEqual(tor.value as? String, "1", "Tor is on by default")
        let status = app.staticTexts["settings-tor-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Tor"), status.label)
        shot(app, "settings-tor")
        tor.switches.firstMatch.tap()
        XCTAssertEqual(tor.value as? String, "0")
        XCTAssertFalse(status.exists)
    }

    /// The Meshtastic radio is off until chosen; turning it on is left to device testing, since it
    /// brings up the Bluetooth permission prompt.
    func testRadioIsOffByDefault() throws {
        let app = openChat()
        app.buttons["online-not-now"].tap()
        app.buttons["settings-button"].tap()
        let radio = app.switches["settings-radio"]
        for _ in 0..<6 where !radio.isHittable { app.swipeUp() }
        XCTAssertTrue(radio.waitForExistence(timeout: 10))
        XCTAssertEqual(radio.value as? String, "0")
        XCTAssertFalse(app.descendants(matching: .any)["radio-status"].exists)
        shot(app, "settings-radio")
    }

    /// Swipe a bubble to the right to reply: a "Replying to" bar shows above the box, the sent reply
    /// quotes the original, and the bar can be cancelled.
    func testSwipeToReplyQuotesTheOriginal() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("bring water")
        app.buttons["chat-send"].tap()
        let original = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: bring water.'")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))

        // Swipe, then cancel: nothing changes.
        original.swipeRight()
        let replying = app.descendants(matching: .any)["chat-replying"]
        XCTAssertTrue(replying.waitForExistence(timeout: 5))
        app.buttons["chat-reply-cancel"].tap()
        XCTAssertFalse(replying.waitForExistence(timeout: 2))

        // Swipe again and answer.
        original.swipeRight()
        XCTAssertTrue(replying.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Replying to your message"].exists)
        shot(app, "chat-replying")
        field.tap()
        field.typeText("how much")
        app.buttons["chat-send"].tap()
        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'You: how much.' AND label CONTAINS 'Reply to you: bring water'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        XCTAssertFalse(replying.exists, "the reply bar closes once the reply is on its way")
        shot(app, "chat-reply-sent")
    }

    /// The box works like Messages: one line when empty, taller as text is added, never taller than
    /// five lines (the rest scrolls inside), and back to one line once sent.
    func testMessageBoxGrowsToFiveLinesThenScrolls() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("one")
        let oneLine = field.frame.height
        field.typeText("\ntwo\nthree")
        let threeLines = field.frame.height
        XCTAssertGreaterThan(threeLines, oneLine + 20, "the box grows with the text")
        field.typeText("\nfour\nfive\nsix\nseven\neight\nnine\nten")
        let tenLines = field.frame.height
        // A long line that wraps, as well as new lines.
        field.typeText(" and a long sentence that wraps across the width of the box more than once, like a real message does")
        let full = field.frame.height
        shot(app, "chat-box-full")
        XCTAssertLessThan(tenLines, oneLine * 6, "ten lines must not make a ten-line box (\(oneLine) -> \(tenLines))")
        XCTAssertEqual(full, tenLines, accuracy: 2, "past five lines the box stops growing and scrolls")
        app.buttons["chat-send"].tap()
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: one'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let box = app.textFields["chat-field"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(box.frame.height, oneLine, accuracy: 2, "after Send the box is one line again")
    }

    /// Long-press a bubble > Delete > confirm: it leaves Chat on this phone. Cancelling keeps it.
    func testLongPressDeletesAMessage() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        field.typeText("delete this one")
        app.buttons["chat-send"].tap()
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You: delete this one.'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))

        bubble.press(forDuration: 1.2)
        let delete = app.buttons["chat-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertTrue(app.buttons["Reply"].exists)
        shot(app, "chat-long-press")
        delete.tap()
        // The dialog shows as a popover, which lists its button twice (same frame): either is the one button.
        let confirm = app.buttons["chat-delete-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot(app, "chat-delete-confirm")
        confirm.tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 5), "the message is gone from Chat")
    }

    /// Chat stays at the newest message: after sending, even when scrolled up to read history; when the
    /// keyboard closes; and when the tab is opened again.
    func testChatStaysAtTheNewestMessage() throws {
        let app = openChat()
        app.buttons["online-on"].tap()
        let field = app.textFields["chat-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count + 5))
        // Enough messages to fill more than a screen.
        for n in 1...12 { send(app, field, "note \(n)") }
        let scroll = app.scrollViews["chat-scroll"]
        XCTAssertTrue(atBottom(app, scroll, "note 12"), "after sending")

        // Scrolled up to read history: sending again comes back down.
        for _ in 0..<3 { scroll.swipeDown() }
        XCTAssertFalse(atBottom(app, scroll, "note 12"), "the swipe scrolled up")
        send(app, field, "note 13")
        XCTAssertTrue(atBottom(app, scroll, "note 13"), "sending while scrolled up")

        // Closing the keyboard (by dragging the conversation) ends at the newest message.
        // Interactive dismissal only closes the keyboard when the drag reaches it, so drag from the
        // conversation down to the bottom of the screen (a swipe inside the scroll view never gets there).
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(atBottom(app, scroll, "note 13"), "after the keyboard closed")

        // Opening the keyboard again keeps the newest message above it.
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(atBottom(app, scroll, "note 13"), "after the keyboard opened")

        // The message box growing a few lines keeps the newest message above it, then back to one line.
        let oneLine = field.frame.height
        field.typeText("a\nb\nc\nd")
        XCTAssertGreaterThan(field.frame.height, oneLine + 20, "the box grew")
        XCTAssertTrue(atBottom(app, scroll, "note 13"), "after the message box grew")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))

        // Leaving Chat and coming back opens at the newest message.
        app.buttons["Receive"].tap()
        app.buttons["Chat"].tap()
        XCTAssertTrue(atBottom(app, app.scrollViews["chat-scroll"], "note 13"), "reopening Chat")
        shot(app, "chat-at-newest")
    }

    private func send(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        if !app.keyboards.firstMatch.exists { field.tap() }
        field.typeText(text)
        app.buttons["chat-send"].tap()
        XCTAssertTrue(bubble(app, text).waitForExistence(timeout: 10), text)
    }

    private func bubble(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "You: \(text).")).firstMatch
    }

    /// The message's bubble is on screen, inside the conversation and above the message box.
    private func atBottom(_ app: XCUIApplication, _ scroll: XCUIElement, _ text: String) -> Bool {
        let b = bubble(app, text), field = app.textFields["chat-field"]
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if b.exists, field.exists, !b.frame.isEmpty,
               b.frame.minY >= scroll.frame.minY - 1, b.frame.maxY <= min(scroll.frame.maxY, field.frame.minY) + 1 { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    /// Turns online chat on, then posts the seeded draft into the demo group's chat as encrypted words
    /// (`sound: false`) or an encrypted sound, which leaves Chat open on that bubble.
    private func postEncrypted(sound: Bool) -> XCUIApplication {
        let app = openChat()
        app.buttons["online-on"].tap()
        XCTAssertTrue(app.textFields["chat-field"].waitForExistence(timeout: 10))
        // By way of Receive: in Chat, "Send" also names the message box's Send key.
        app.buttons["Receive"].tap()
        app.buttons["Send"].tap()
        let key = app.buttons[sound ? "play-tones" : "copy-words"]
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        key.tap()
        let post = app.buttons["post-chat-send"]
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        for _ in 0..<3 where !post.isHittable { app.swipeUp() }
        post.tap()
        XCTAssertTrue(app.buttons[sound ? "chat-carried-sound" : "chat-carried-words"].waitForExistence(timeout: 10))
        return app
    }

    /// A tap on encrypted words opens a small menu on the bubble (Copy, Decrypt) and nothing else: Chat
    /// stays, nothing is copied. A tap outside closes it. Decrypt then opens the message in Receive.
    func testTapOnEncryptedWordsShowsAMenuAndDoesNotLeaveChat() throws {
        let app = postEncrypted(sound: false)
        let bubble = app.buttons["chat-carried-words"]
        bubble.tap()
        let copy = app.buttons["Copy"], decrypt = app.buttons["Decrypt"]
        XCTAssertTrue(decrypt.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.exists)
        XCTAssertFalse(app.descendants(matching: .any)["paste-field"].exists, "Receive did not open")
        XCTAssertFalse(app.staticTexts["chat-copied-words"].exists, "nothing was copied")
        shot(app, "encrypted-words-menu")

        // A tap outside closes the menu and costs nothing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(decrypt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["chat-field"].exists, "still in Chat")

        bubble.tap()
        XCTAssertTrue(decrypt.waitForExistence(timeout: 5))
        decrypt.tap()
        XCTAssertTrue(app.staticTexts["decoded-text"].waitForExistence(timeout: 10), "Decrypt opens it in Receive")
    }

    /// The same for an encrypted sound, which used to jump straight to Receive on a tap.
    func testTapOnEncryptedSoundShowsAMenuAndDoesNotLeaveChat() throws {
        let app = postEncrypted(sound: true)
        let bubble = app.buttons["chat-carried-sound"]
        bubble.tap()
        let decrypt = app.buttons["Decrypt"]
        XCTAssertTrue(decrypt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy"].exists)
        XCTAssertFalse(app.buttons["decrypt-sound"].exists, "Receive did not open")
        XCTAssertTrue(app.textFields["chat-field"].exists, "still in Chat")
        shot(app, "encrypted-sound-menu")
        decrypt.tap()
        XCTAssertTrue(app.buttons["decrypt-sound"].waitForExistence(timeout: 10), "Decrypt opens it in Receive")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
