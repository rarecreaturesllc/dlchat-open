import XCTest

/// T025: the pressure-mark toggle, confirmations before irreversible changes, and the system
/// accessibility audit on the main screens. Uses the throwaway `-seed-demo` vault.
final class UXBaselineUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo"] + extra
        app.launch()
        let show = app.buttons["Show the words"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: show)
        waitForExpectations(timeout: 10)
        return app
    }

    /// The message box is taller than its text (four lines and padding); a tap on the empty part must still open typing.
    func testTappingTheEmptyPartOfTheMessageBoxStartsTyping() throws {
        let app = launch()
        let field = app.descendants(matching: .any)["compose-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 90)).tap()
        app.typeText(" now")
        XCTAssertEqual(field.value as? String, "need water at north gate now")
    }

    /// The word count stays put while typing (no hint pops in, the box does not grow), and the return
    /// key (the check mark) closes the keyboard without adding a line break.
    func testCountStaysStillAndReturnClosesTheKeyboard() throws {
        let app = launch()
        let field = app.descendants(matching: .any)["compose-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let count = app.staticTexts["words to say"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        field.tap()
        let before = count.frame.minY
        app.typeText(" zorbly and more words to make a long message that wraps onto several lines of the box")
        XCTAssertEqual(count.frame.minY, before, accuracy: 0.5)
        app.typeText("\n")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 5))
        XCTAssertFalse((field.value as? String ?? "").contains("\n"))
    }

    /// Same for the 140 pt phrase box on Join group, the first thing a new tester types into.
    func testTappingTheEmptyPartOfThePhraseBoxStartsTyping() throws {
        let app = launch(["-screen", "create"])
        let join = app.buttons["Join"]
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        join.tap()
        let phrase = app.descendants(matching: .any)["join-phrase"].firstMatch
        XCTAssertTrue(phrase.waitForExistence(timeout: 10))
        phrase.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 90)).tap()
        app.typeText("apple")
        XCTAssertEqual(phrase.value as? String, "apple")
    }

    func testPressureMarkToggleIsInSafety() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let toggle = app.switches["safety-pressure"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    /// The PIN is required: Settings > Safety offers no way to remove it, only to change it (typed twice).
    func testPINCanBeChangedButNotRemoved() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let fold = app.buttons["safety-fold-pin"]
        XCTAssertTrue(fold.waitForExistence(timeout: 10))
        fold.tap()
        let pin = app.secureTextFields["safety-New PIN"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["safety-remove-pin"].exists)
        XCTAssertFalse(app.buttons["Remove PIN"].exists)
        let again = app.secureTextFields["safety-New PIN again"]

        pin.tap(); pin.typeText("135790")
        again.tap(); again.typeText("135791")
        app.staticTexts["safety-pin-about"].tap()
        app.buttons["safety-change-pin"].tap()
        XCTAssertTrue(app.staticTexts["The two PINs did not match."].waitForExistence(timeout: 5))

        pin.tap(); pin.typeText("135790")
        again.tap(); again.typeText("135790")
        app.staticTexts["safety-pin-about"].tap()
        app.buttons["safety-change-pin"].tap()
        XCTAssertTrue(app.staticTexts["PIN changed."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.buttons["lock-now"].tap()
        let unlock = app.buttons["lock-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        for digit in "246810" { app.buttons[String(digit)].tap() }
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Wrong PIN."].waitForExistence(timeout: 5), "the old PIN no longer opens it")
        for digit in "135790" { app.buttons[String(digit)].tap() }
        unlock.tap()
        XCTAssertTrue(app.buttons["Show the words"].waitForExistence(timeout: 10))
    }

    func testShorterRetentionAsksFirst() throws {
        let app = launch()
        app.buttons["settings-button"].tap()
        let picker = app.buttons["settings-retention"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons["1 day"].tap()
        let confirm = app.buttons["Erase older messages"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.buttons["settings-retention"].waitForExistence(timeout: 10))
    }

    func testAccessibilityAuditOnTheMainScreens() throws {
        let app = launch()
        try audit(app)

        app.buttons["Receive"].tap()
        try audit(app)
        app.buttons["Send"].tap()

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10))
        let settings = app.scrollViews["settings-scroll"]
        try audit(app, clippedBy: settings)
        // Settings (which holds Safety) is longer than the screen: the rows below the first screen are audited once scrolled to.
        // Wait for the fling to stop: an audit taken mid-scroll samples pixels from a different offset than the frames.
        let title = app.staticTexts["Settings"]
        for _ in 0..<3 { settings.swipeUp(); waitUntilStill(title); try audit(app, clippedBy: settings) }
        // Scrolled to the bottom, Done and the title are still in view: the header is pinned.
        XCTAssertTrue(app.buttons["settings-done"].isHittable, "Done stays reachable at the bottom of Settings")
        XCTAssertTrue(title.isHittable)
        app.buttons["Done"].tap()
    }

    /// The Map tab (demo radios, demo location; no Tor, so the radar), in both views and a radio's details.
    func testAccessibilityAuditOnTheMeshMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed-demo", "-reset-demo", "-screen", "meshmap"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mesh map"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["meshmap-radar"].waitForExistence(timeout: 10))
        try audit(app)
        app.buttons["meshmap-units"].tap()
        try audit(app)
        // Radar: first tap shows the bubble, a tap on the bubble opens the details.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hilltop relay'")).firstMatch.tap()
        let bubble = app.buttons["meshmap-bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        try audit(app)
        bubble.tap()
        XCTAssertTrue(app.staticTexts["Radio ID"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["Porch radio"].waitForExistence(timeout: 10))
        try audit(app)
        app.staticTexts["Porch radio"].tap()
        XCTAssertTrue(app.staticTexts["Radio ID"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["!000000a1"].exists)
        try audit(app)
    }

    /// Returns once the element's frame stops changing between two looks 0.25 s apart (scrolling has ended).
    private func waitUntilStill(_ element: XCUIElement) {
        var last = element.frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = element.frame
            if now == last { return }
            last = now
        }
    }

    /// Runs the system audit. Three recorded exceptions (docs/ux-baseline.md, "Accessibility audit"):
    /// 1. The Dynamic Type check is reported on buttons and text that sit in a `ViewThatFits` (the top
    ///    bar, `ButtonPair`, the Send screen). The audit changes the text size, the layout swaps, and
    ///    it cannot follow the element, so it calls the font unsupported. Dynamic Type is checked by
    ///    the AXXL and AXXXL screenshots instead.
    /// 2. A contrast finding on a disabled control: dimmed on purpose and exempt (WCAG 1.4.3).
    /// 3. A contrast finding on an element cut off by the screen edge or by the edge of `clip` (a scroll view):
    ///    the audit samples the pixels past the edge, not the element's own background. Settings is audited
    ///    at several scroll positions, so each row is also checked whole.
    /// Every other finding fails the test.
    private func audit(_ app: XCUIApplication, clippedBy clip: XCUIElement? = nil) throws {
        let window = app.windows.firstMatch.frame
        let visible = clip.map { $0.frame.intersection(window) } ?? window
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            // Disabled controls are dimmed on purpose and exempt from contrast rules (WCAG 1.4.3).
            if issue.auditType == .contrast {
                guard let element else { return false }
                return !element.isEnabled || !visible.contains(element.frame)
            }
            guard issue.auditType == .dynamicType else { return false }
            return element?.elementType == .button || element?.elementType == .staticText
        }
    }
}
