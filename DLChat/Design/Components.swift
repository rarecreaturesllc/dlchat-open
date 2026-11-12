import SwiftUI
import UIKit

// Reusable pieces from DESIGN.md. Screens compose these and add no styling of their own.

/// Every button is felt as well as seen. `DLButtonStyle` taps on its own; other buttons call `tap()` in their action.
/// iOS skips all of these when System Haptics is off in the iPhone's Settings.
enum Haptics {
    /// A light tap for any button press.
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// A tick for moving between choices (tabs, Send/Receive, map range).
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Something the button asked for did not happen.
    static func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    /// It is done and known to be done (joined, scanned, saved), never before the outcome is known.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// It failed and needs attention (wrong PIN, a message that could not go).
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// The press of a key that draws its own face (PIN digits, the top bar's keys, Chat's Send key, word
/// suggestions): it goes down 3% like a bar does, and nothing else about it changes. The haptic stays
/// with the button's action. The scale is small enough to keep with Reduce Motion on.
struct DLPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DLMotion.pressScale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(DLMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DLPressStyle {
    static var dlPress: DLPressStyle { .init() }
}

struct DLButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        // Primary: the one neon pill. Secondary: a bone outline, so green stays reserved. Danger: red on panel.
        // Disabled: panel with soft ink and an outline, legible but plainly not ready (a faded neon pill read as broken).
        let fill: Color = switch kind { case .primary: enabled ? .dlGo : .dlPanel; case .secondary: .clear; case .danger: .dlPanel }
        let ink: Color = switch kind {
        case _ where !enabled: .dlSoft
        case .primary: .dlNight
        case .secondary: .dlText
        case .danger: .dlWarn
        }
        configuration.label
            .font(.dl(.title3, .bold))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DLSpace.xs)
            .padding(.horizontal, DLSpace.lg)
            .frame(maxWidth: .infinity, minHeight: DLSize.primary)
            .background(fill, in: RoundedRectangle.key)
            .overlay {
                if kind != .primary || !enabled {
                    RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : (enabled ? Color.dlEdge : Color.dlHairline), lineWidth: contrast == .increased ? 2 : 1)
                }
            }
            .animation(.snappy(duration: 0.2), value: enabled)
            .scaleEffect(configuration.isPressed ? DLMotion.pressScale : 1)
            .animation(DLMotion.press, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == DLButtonStyle {
    static var dlPrimary: DLButtonStyle { .init(kind: .primary) }
    static var dlSecondary: DLButtonStyle { .init(kind: .secondary) }
    static var dlDanger: DLButtonStyle { .init(kind: .danger) }
}

/// Fields need their own edge: Panel Slate on Night Slate is only about 1.15:1 (the Edge Rule).
struct DLFieldStyle: ViewModifier {
    var focused: Bool
    var minHeight: CGFloat = 0
    /// Focuses the field from anywhere in the box. The text field is smaller than the box (padding, minHeight),
    /// so without this a tap there misses it, or hits a screen's dismiss-keyboard gesture.
    var onTap: (() -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .font(.dl(.title2))
            .foregroundStyle(Color.dlText)
            .padding(18)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay(RoundedRectangle.key.stroke(focused ? Color.dlGo : Color.dlSoft, lineWidth: focused ? 2 : (contrast == .increased ? 2.5 : 1.5)))
            .contentShape(RoundedRectangle.key)
            .onTapGesture { onTap?() }
    }
}

/// Every chat's message box (group Chat, Meshtastic chats, Internet Messages) works like Messages:
/// one line when empty, taller with each line of text up to `maxLines`, then the text scrolls inside
/// the box. After Send the box is empty again, so it drops back to one line.
struct ChatBoxStyle: ViewModifier {
    static let maxLines = 5
    func body(content: Content) -> some View {
        content
            .lineLimit(1...Self.maxLines)
            .font(.dl(.body))
            .foregroundStyle(Color.dlText)
            .padding(.vertical, 12)
            .frame(minHeight: DLSize.control)
    }
}

extension View {
    func chatBox() -> some View { modifier(ChatBoxStyle()) }

    func dlField(focused: Bool, minHeight: CGFloat = 0, onTap: (() -> Void)? = nil) -> some View {
        modifier(DLFieldStyle(focused: focused, minHeight: minHeight, onTap: onTap))
    }
}

struct WordChip: View {
    let word: String
    var missing = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Text(word)
            .font(.dl(.callout, .semibold))
            .foregroundStyle(missing ? Color.dlWarn : Color.dlText)
            .minimumScaleFactor(0.7).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: DLSize.control)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay(RoundedRectangle.key.stroke(missing ? Color.dlWarn : (contrast == .increased ? Color.dlSoft : Color.dlHairline), lineWidth: missing || contrast == .increased ? 2 : 1))
            .accessibilityLabel(word == "?" ? "Missing word" : missing ? "\(word), not on the word list" : word)
    }
}

/// Send / Receive: the active mode is Console White, so green stays reserved for the one primary action.
struct ModeSwitch: View {
    @Binding var mode: Int
    let labels: [String]
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: DLSpace.sm) {
            ForEach(labels.indices, id: \.self) { i in
                Button { Haptics.select(); withAnimation(reduceMotion ? nil : DLMotion.press) { mode = i } } label: {
                    Text(labels[i])
                        .font(.dl(.title3, .bold))
                        .foregroundStyle(mode == i ? Color.dlNight : Color.dlSoft)
                        .minimumScaleFactor(0.7).lineLimit(1)
                        .padding(.horizontal, DLSpace.md)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(mode == i ? Color.dlText : Color.dlPanel, in: RoundedRectangle.key)
                        .overlay { if contrast == .increased && mode != i { RoundedRectangle.key.stroke(Color.dlSoft, lineWidth: 2) } }
                }
                .accessibilityAddTraits(mode == i ? .isSelected : [])
            }
        }
    }
}

/// The app's main sections as a slider under the top bar: always on screen, keyboard up or not,
/// so no section can trap you. The highlight slides to the chosen tab.
struct TabSlider: View {
    @Binding var selection: Int
    let labels: [String]
    var body: some View {
        DLSegments(selection: $selection, options: Array(labels.indices)) { labels[$0] }
    }
}

/// A few exclusive choices as squared segments with mono caps legends (the tabs, and wherever a
/// segmented picker would go). The chosen segment is a bone key that slides to its place.
struct DLSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Namespace private var highlight
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility text sizes the segments go two to a row, so a legend is never broken mid-word.
        let columns = typeSize.isAccessibilitySize ? min(2, options.count) : options.count
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(columns, 1)), spacing: 0) {
            ForEach(options, id: \.self) { option in
                // Not withAnimation: that would cross-fade the whole screen below. Only the highlight moves
                // (the .animation below); the content swaps at once, like a system tab bar.
                Button { Haptics.select(); selection = option } label: {
                    Text(title(option).uppercased())
                        .dlCaps(.footnote)
                        .accessibilityLabel(title(option))
                        .foregroundStyle(selection == option ? Color.dlNight : Color.dlSoft)
                        .lineLimit(typeSize.isAccessibilitySize ? 1 : 2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                        .padding(.horizontal, DLSpace.xs)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selection == option {
                                RoundedRectangle.inner.fill(Color.dlText).padding(4).matchedGeometryEffect(id: "segment", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        // Compact bar: the highlight is inset 4pt, but each segment keeps a full 44pt tap area.
        .animation(reduceMotion ? nil : DLMotion.move, value: selection)
        .background(Color.dlPanel, in: RoundedRectangle.key)
        .overlay { RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : Color.dlHairline, lineWidth: contrast == .increased ? DLStroke.strong : DLStroke.hair) }
    }
}

/// Wipe needs a deliberate 3 second hold. VoiceOver gets a custom action, since holding is a gesture.
struct HoldToWipeButton: View {
    var seconds = 3.0
    /// Returns false when the wipe did not finish; the button then says so and can be held again.
    let onWipe: () -> Bool
    @State private var held = false
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DLSpace.xs) {
            button
            if failed {
                Text("The wipe did not finish, so some data may remain. Hold again to retry.")
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                    .multilineTextAlignment(.center).accessibilityIdentifier("wipe-failed")
            }
        }
    }

    private func wipe() {
        failed = !onWipe()
    }

    private var button: some View {
        Text(held ? "Keep holding…" : "Hold to wipe everything")
            .font(.dl(.title3, .bold))
            .foregroundStyle(Color.dlWarn)
            .frame(maxWidth: .infinity, minHeight: DLSize.primary)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().fill(Color.dlWarn.opacity(0.28))
                        .frame(width: held ? geo.size.width : 0)
                        .animation(held ? .linear(duration: seconds) : .easeOut(duration: reduceMotion ? 0 : 0.2), value: held)
                }
            }
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .clipShape(RoundedRectangle.key)
            .overlay { RoundedRectangle.key.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
            .contentShape(RoundedRectangle.key)
            .onLongPressGesture(minimumDuration: seconds, maximumDistance: 40, perform: {
                Haptics.warn()
                held = false
                wipe()
            }, onPressingChanged: { pressing in if pressing { Haptics.tap() }; held = pressing })
            .accessibilityElement()
            .accessibilityLabel("Wipe everything")
            .accessibilityHint("Press and hold for three seconds. Erases all groups, phrases and messages. This cannot be undone.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Wipe everything now", wipe)
    }
}

/// Two buttons side by side, stacked once text is large enough that labels would truncate.
struct ButtonPair<A: View, B: View>: View {
    @ViewBuilder var first: A
    @ViewBuilder var second: B
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DLSpace.sm) { first; second }
            VStack(spacing: DLSpace.sm) { first; second }
        }
    }
}

/// Picks how long received messages are kept. Choosing a shorter time erases messages at once and
/// cannot be undone, so it asks first.
struct RetentionPicker: View {
    let groups: GroupModel
    var changed: () -> Void = {}
    @State private var pending: Retention?

    private func isShorter(_ new: Retention) -> Bool {
        let old = groups.retention.seconds ?? .infinity
        return (new.seconds ?? .infinity) < old
    }

    var body: some View {
        Picker("Keep messages for", selection: Binding(get: { groups.retention }, set: choose)) {
            ForEach(Retention.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu).frame(minHeight: DLSize.control)
        .confirmationDialog("Keep messages for \(pending?.title ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Erase older messages", role: .destructive) {
                Haptics.tap()
                if let pending { groups.setRetention(pending); changed() }
                pending = nil
            }
        } message: {
            Text("Messages older than this are erased now. This cannot be undone.")
        }
    }

    private func choose(_ new: Retention) {
        if isShorter(new) { pending = new } else { groups.setRetention(new); changed() }
    }
}

/// A squared key with an icon over its label: the other carriers on Send, the ways in on Receive.
struct DLKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dl(.footnote, .semibold))
            .foregroundStyle(enabled ? Color.dlText : Color.dlSoft)
            .frame(maxWidth: .infinity, minHeight: DLSize.primary)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay { RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : (enabled ? Color.dlEdge : Color.dlHairline), lineWidth: contrast == .increased ? DLStroke.strong : DLStroke.hair) }
            .scaleEffect(configuration.isPressed ? DLMotion.pressScale : 1)
            .animation(DLMotion.press, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// The label inside a `DLKeyStyle` button.
struct KeyLabel: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.dl(.title3, .semibold)).frame(minHeight: 26).accessibilityHidden(true)
            Text(title).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4).padding(.vertical, DLSpace.xs)
    }
}

/// A row of keys, stacked once text is large enough that their labels would truncate.
struct KeyRow<Keys: View>: View {
    @ViewBuilder var keys: Keys
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: DLSpace.xs) { keys }
        } else {
            HStack(spacing: DLSpace.xs) { keys }
        }
    }
}

/// The recessed readout window: a number in mono digits and up to two legend lines beside it.
struct Readout: View {
    let value: String
    let legend: String
    var detail: String?
    @ScaledMetric(relativeTo: .largeTitle) private var size = 42

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DLSpace.sm) { digits; legends; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 4) { digits; legends }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.xs)
        .background(Color.dlWell, in: RoundedRectangle.key)
        .overlay { RoundedRectangle.key.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var digits: some View {
        Text(value).font(.system(size: size, weight: .semibold, design: .monospaced)).foregroundStyle(Color.dlText)
            .lineLimit(1).minimumScaleFactor(0.6)
            // "07" is read as seven, not zero seven.
            .accessibilityLabel(Int(value).map(String.init) ?? value)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : DLMotion.move, value: value)
    }

    private var legends: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(legend.uppercased()).dlCaps(.footnote).foregroundStyle(Color.dlText).accessibilityLabel(legend)
            if let detail { Text(detail.uppercased()).dlCaps(.caption).foregroundStyle(Color.dlSoft).accessibilityLabel(detail) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One message in any chat, laid out like Messages: yours on the right on a raised panel, everyone
/// else's on the left in a recessed well. Sides differ by place and fill, never by colour alone. The
/// day and time sit in mono at the foot of the bubble.
struct LogRow<Content: View>: View {
    let time: String
    /// The day, for a message that is not from today.
    var day: String?
    let mine: Bool
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // The far side keeps a gap so a long message still reads as left or right; narrower at accessibility sizes.
        let gap: CGFloat = typeSize.isAccessibilitySize ? DLSpace.md : 48
        HStack(spacing: 0) {
            if mine { Spacer(minLength: gap) }
            VStack(alignment: .leading, spacing: 6) {
                content
                Text((day.map { $0.uppercased() + " " } ?? "") + time).font(.dlMono(.caption2, .medium)).foregroundStyle(Color.dlSoft)
            }
            .padding(.horizontal, DLSpace.sm).padding(.vertical, 10)
            .background(mine ? Color.dlPanel : Color.dlWell, in: RoundedRectangle.key)
            .overlay { RoundedRectangle.key.stroke(contrast == .increased ? Color.dlSoft : Color.dlEdge, lineWidth: contrast == .increased ? DLStroke.strong : DLStroke.hair) }
            if !mine { Spacer(minLength: gap) }
        }
        .padding(.horizontal, DLSpace.md).padding(.vertical, 3)
    }
}

/// Progress as a row of segments, one per step (the read-out's groups of three): lit up to the current one.
struct SegmentMeter: View {
    let step: Int
    let total: Int
    var body: some View {
        HStack(spacing: total > 24 ? 1 : 3) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Rectangle().fill(i < step ? Color.dlGo : Color.dlEdge).frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(step) of \(total)")
    }
}

/// A level or playback meter: a squared bar in a well, green as far as it has got.
struct DLMeterStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.dlGo).frame(width: geo.size.width * (configuration.fractionCompleted ?? 0))
        }
        .frame(height: 6)
        .background(Color.dlEdge)
    }
}

/// A section legend: mono caps under a hairline, like the printed label over a group of controls.
struct DLLegend: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            Rectangle().fill(Color.dlHairline).frame(height: DLStroke.hair)
            Text(text.uppercased()).dlCaps(.footnote).foregroundStyle(Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DLSpace.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits([.isHeader, .isStaticText])
    }
}
