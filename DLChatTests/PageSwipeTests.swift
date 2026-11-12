import XCTest
@testable import DLChat

/// Swiping the page left or right moves between Send, Receive, Chat and Map.
final class PageSwipeTests: XCTestCase {
    func testASidewaysDragMovesOneTab() {
        XCTAssertEqual(PageSwipe.page(from: 0, translation: CGSize(width: -120, height: 10), count: 4), 1)
        XCTAssertEqual(PageSwipe.page(from: 2, translation: CGSize(width: 120, height: -10), count: 4), 1)
        XCTAssertEqual(PageSwipe.page(from: 2, translation: CGSize(width: -60, height: 0), count: 4), 3)
    }

    func testTheEndsDoNotWrapAround() {
        XCTAssertNil(PageSwipe.page(from: 0, translation: CGSize(width: 200, height: 0), count: 4))
        XCTAssertNil(PageSwipe.page(from: 3, translation: CGSize(width: -200, height: 0), count: 4))
    }

    func testShortOrSlantedDragsAreNotPageSwipes() {
        XCTAssertNil(PageSwipe.step(CGSize(width: -59, height: 0)), "too short")
        XCTAssertNil(PageSwipe.step(CGSize(width: -100, height: 60)), "more of a scroll than a swipe")
        XCTAssertNil(PageSwipe.step(CGSize(width: 0, height: -300)), "scrolling up")
        XCTAssertNil(PageSwipe.step(CGSize(width: 40, height: 300)), "scrolling down with some drift")
    }

    @MainActor func testADragClaimedForReplyIsNotAPageSwipe() {
        PageSwipe.replyClaim = CGPoint(x: 80, y: 400)
        XCTAssertTrue(PageSwipe.claimedForReply(CGPoint(x: 80.5, y: 400)))
        XCTAssertFalse(PageSwipe.claimedForReply(CGPoint(x: 80, y: 300)), "another drag, somewhere else")
        PageSwipe.replyClaim = nil
        XCTAssertFalse(PageSwipe.claimedForReply(CGPoint(x: 80, y: 400)))
    }
}
