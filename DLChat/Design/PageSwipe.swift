import SwiftUI
import UIKit

/// A UIKit view that uses sideways drags itself (the street map), so a swipe starting on it never changes tab.
@MainActor protocol SideSwipeOwner: UIView {}

/// Swiping left or right on a main screen moves to the next or previous tab (Send, Receive, Chat, Map).
/// The tab slider still works as before; this is a second way to do the same thing.
///
/// A sideways drag that something on the screen already uses is left alone:
/// - a chat bubble being swiped right to reply (`replyClaim`),
/// - the street map, which pans,
/// - a text box, where a drag moves the cursor or the selection,
/// - a row that scrolls sideways (the word suggestions on Receive).
enum PageSwipe {
    /// How far the finger must travel sideways.
    static let distance: CGFloat = 60

    /// +1 for the next tab (finger moved left), -1 for the previous one, nil when the drag is not a page swipe:
    /// too short, or not clearly sideways (so scrolling up and down never changes tab).
    static func step(_ translation: CGSize) -> Int? {
        guard abs(translation.width) >= distance, abs(translation.width) >= abs(translation.height) * 2 else { return nil }
        return translation.width < 0 ? 1 : -1
    }

    /// The tab a drag from `page` lands on, or nil when it stays put. The ends do not wrap around.
    static func page(from page: Int, translation: CGSize, count: Int) -> Int? {
        guard let step = step(translation) else { return nil }
        let next = page + step
        return (0..<count).contains(next) ? next : nil
    }

    /// Where the drag that is swiping a chat bubble to reply started, in screen points.
    @MainActor static var replyClaim: CGPoint?

    /// True when the drag that began at `start` is the one a chat bubble claimed for reply.
    @MainActor static func claimedForReply(_ start: CGPoint) -> Bool {
        guard let claim = replyClaim else { return false }
        return abs(claim.x - start.x) < 2 && abs(claim.y - start.y) < 2
    }

    /// True when the point is on something that uses sideways drags itself: the map, a text box,
    /// or a row that scrolls sideways.
    @MainActor static func isOwned(_ point: CGPoint) -> Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: { $0.windowLevel == .normal && $0.isKeyWindow })
                ?? windows.first(where: { $0.windowLevel == .normal }) else { return false }
        var view = window.hitTest(point, with: nil)
        while let found = view {
            if found is SideSwipeOwner || found is UITextInput { return true }
            if let scroll = found as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 { return true }
            view = found.superview
        }
        return false
    }
}

private struct PageSwipeModifier: ViewModifier {
    @Binding var page: Int
    let count: Int
    /// A strip this wide along the leading edge is left to something else (an open conversation's
    /// swipe back to the Chat list), so a drag starting there never changes tab.
    let leadingEdge: CGFloat
    @Environment(\.layoutDirection) private var direction
    /// A page swipe is under way: the buttons under the finger are switched off, so lifting it on one
    /// (a key on Send is narrower than a swipe) changes tab without also pressing that button.
    @State private var swiping = false
    /// Resets by itself when the drag ends or is cancelled, so `swiping` can never stay on.
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        content
            .disabled(swiping)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .updating($dragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        if !swiping, isPageSwipe(value) { swiping = true }
                    }
                    .onEnded { value in
                        defer { PageSwipe.replyClaim = nil }
                        guard isPageSwipe(value),
                              let next = PageSwipe.page(from: page, translation: value.translation, count: count) else { return }
                        Haptics.select()
                        page = next
                    })
            // Buttons back on only after the lift has been handled, so the button under the finger stays off for it.
            .onChange(of: dragging) { _, now in if !now { Task { @MainActor in swiping = false } } }
    }

    private func isPageSwipe(_ value: DragGesture.Value) -> Bool {
        PageSwipe.page(from: page, translation: value.translation, count: count) != nil
            && !startsAtLeadingEdge(value.startLocation)
            && !PageSwipe.claimedForReply(value.startLocation)
            && !PageSwipe.isOwned(value.startLocation)
    }

    private func startsAtLeadingEdge(_ point: CGPoint) -> Bool {
        guard leadingEdge > 0 else { return false }
        if direction == .rightToLeft {
            let width = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width ?? 0
            return point.x > width - leadingEdge
        }
        return point.x < leadingEdge
    }
}

extension View {
    /// Swiping left or right on this view moves `page` forward or back, within `0..<count`. A drag that
    /// starts within `leadingEdge` points of the leading edge is left alone.
    func pageSwipe(_ page: Binding<Int>, count: Int, leadingEdge: CGFloat = 0) -> some View {
        modifier(PageSwipeModifier(page: page, count: count, leadingEdge: leadingEdge))
    }
}
