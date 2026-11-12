import SwiftUI
import UIKit

/// Shows its content only while a finger is held on the button; letting go hides it again.
/// VoiceOver gets a Show / Hide action instead, since holding is a gesture.
struct HoldToReveal<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    /// Resets by itself when the touch ends or iOS cancels it, so a lost touch can never leave the content showing.
    @GestureState private var held = false
    @State private var toggled = Self.revealedForTests

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool { held || toggled }

    /// UI tests cannot read text that shows only while a finger is down; DEBUG builds can start shown.
    private static var revealedForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-reveal-held")
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            // Fades in once held; gone at once on letting go, never fading out.
            if shown { content.transition(.asymmetric(insertion: .opacity, removal: .identity)) }
            Text(shown ? "Let go to hide it" : title)
                .font(.dl(.title3, .bold)).foregroundStyle(Color.dlGo)
                .frame(maxWidth: .infinity, minHeight: DLSize.primary)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($held) { _, held, _ in held = true })
                .onChange(of: held) { _, now in if now { Haptics.tap() } }
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("hold-reveal")
                .accessibilityAction(named: toggled ? "Hide" : "Show") { toggled.toggle() }
        }
        .animation(reduceMotion ? nil : DLMotion.press, value: shown)
        .onDisappear { toggled = false }
    }
}
