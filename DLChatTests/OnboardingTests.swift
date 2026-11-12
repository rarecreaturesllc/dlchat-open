@testable import DLChat
import XCTest

/// The first-run group question: asked once, only with no group, and again after a wipe.
final class OnboardingTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "app.dlchat.tests.\(UUID().uuidString)"))
    }

    func testAskedOnFirstRunWithNoGroup() throws {
        let d = try defaults()
        XCTAssertTrue(Onboarding.shouldAsk(hasGroups: false, defaults: d))
    }

    func testNeverAskedWhenAGroupIsAlreadySaved() throws {
        let d = try defaults()
        XCTAssertFalse(Onboarding.shouldAsk(hasGroups: true, defaults: d), "an update with groups never sees it")
    }

    func testSkipIsRemembered() throws {
        let d = try defaults()
        Onboarding.markDone(d)
        XCTAssertFalse(Onboarding.shouldAsk(hasGroups: false, defaults: d), "after Skip the app opens with no group")
        Onboarding.reset(d)
        XCTAssertTrue(Onboarding.shouldAsk(hasGroups: false, defaults: d))
    }
}
