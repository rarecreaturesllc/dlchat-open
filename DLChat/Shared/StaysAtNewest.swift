import SwiftUI
import UIKit

extension View {
    /// Keeps a message list at its newest message. Every conversation uses this one behavior, so they
    /// all scroll the same way: group Chat, Internet Messages, and the Meshtastic channels and radios.
    func stayingAtNewest<ID: Hashable>(_ proxy: ScrollViewProxy, conversation: AnyHashable?, newest: ID?) -> some View {
        modifier(StaysAtNewest(proxy: proxy, conversation: conversation, newest: newest))
    }
}

/// Keeps a conversation at its newest message, as the owner asked: it opens at the bottom, follows every
/// new message (sent or received, even when the person had scrolled up to read history), and stays at
/// the bottom when the keyboard opens or closes, the message box grows a line, or a bubble grows
/// (e.g. "waiting" turning into "sent").
struct StaysAtNewest<ID: Hashable>: ViewModifier {
    let proxy: ScrollViewProxy
    /// Which conversation is showing (the group, the contact, or the Meshtastic chat): a change jumps without gliding.
    let conversation: AnyHashable?
    let newest: ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The visible height last seen (the two-value onGeometryChange needs iOS 18; this runs on 17).
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Starts at the bottom, and holds the bottom when the content or the visible area changes size.
            .defaultScrollAnchor(.bottom)
            .onChange(of: Place(conversation: conversation, newest: newest), initial: true) { old, now in
                // Opening or switching conversations jumps; a new message in the same one glides.
                // The first call (on opening) passes the same value twice, so it must not count as a new message.
                toBottom(animated: old != now && old.conversation == now.conversation && old.newest != nil)
            }
            // The visible area got shorter: the keyboard is coming up or the message box grew a line.
            // Only on shrinking, so dragging the keyboard down to close it is never fought mid-drag.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { now in
                let shrank = height > 0 && now < height - 1
                height = now
                if shrank { toBottom(animated: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in toBottom(animated: true) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in toBottom(animated: true) }
    }

    private struct Place: Equatable { let conversation: AnyHashable?, newest: ID? }

    private func toBottom(animated: Bool) {
        guard let newest else { return }
        if animated && !reduceMotion {
            withAnimation(DLMotion.exit) { proxy.scrollTo(newest, anchor: .bottom) }
        } else {
            proxy.scrollTo(newest, anchor: .bottom)
        }
    }
}
