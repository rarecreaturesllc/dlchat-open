import SwiftUI

/// What the relay and radio lines at the top of Chat boil down to, so they can fold into one line.
/// Kept apart from the view so the wording and the "never hide a problem" rule are unit tested.
struct ChatStatusFold: Equatable {
    enum Part: Equatable { case active, connecting, off, attention }

    let relays: Part
    /// Nil while the radio is turned off: it has no line then.
    let radio: Part?

    /// Something is wrong or needs the person (Tor failed, radio out of reach, Bluetooth off, …).
    /// The full lines then stay open and do not fold.
    var needsAttention: Bool { relays == .attention || radio == .attention }

    var anyActive: Bool { relays == .active || radio == .active }

    /// One short line, e.g. "Relay and radio active", "Radio active · relay connecting", "Online chat is off".
    var summary: String {
        var active: [String] = [], connecting: [String] = []
        for (name, part) in [("relay", relays), ("radio", radio)] {
            if part == .active { active.append(name) }
            if part == .connecting { connecting.append(name) }
        }
        var phrases: [String] = []
        if !active.isEmpty { phrases.append(active.joined(separator: " and ") + " active") }
        if !connecting.isEmpty { phrases.append(connecting.joined(separator: " and ") + " connecting") }
        if relays == .off { phrases.append("online chat is off") }
        let text = phrases.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func relays(isOn: Bool, torOn: Bool, torReady: Bool, torFailed: Bool, connected: Int) -> Part {
        guard isOn else { return .off }
        if torOn, !torReady { return torFailed ? .attention : .connecting }
        return connected > 0 ? .active : .connecting
    }

    /// Mirrors `MeshStatus.text`: only "sending and receiving by radio" counts as active.
    static func radio(isOn: Bool, problem: String?, licensed: Bool, applying: Bool, regionUnset: Bool,
                      status: MeshtasticModel.Status, isMine: Bool, letGoByHand: Bool) -> Part? {
        guard isOn else { return nil }
        if problem != nil || licensed { return .attention }
        if applying { return .connecting }
        switch status {
        case .ready: return regionUnset || !isMine ? .attention : .active
        case .off, .searching, .connecting: return .connecting
        case .released: return letGoByHand ? .attention : .connecting
        case .bluetoothOff, .unauthorized, .disconnected, .busy: return .attention
        }
    }
}

/// The relay and radio status at the top of Chat: one short line, always folded when a conversation
/// opens. Tapping it opens the full lines over the top of the messages (so the list below does not
/// move), and tapping again folds them. While something needs attention the full lines show, with
/// their own room, so a problem is never hidden.
struct ChatStatusHeader: View {
    let online: OnlineModel
    let mesh: MeshtasticModel

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fold: ChatStatusFold {
        _ = mesh.mineVersion
        return ChatStatusFold(
            relays: ChatStatusFold.relays(isOn: online.isOn, torOn: online.torOn, torReady: online.torPort != nil,
                                          torFailed: online.torFailed, connected: online.connected),
            radio: ChatStatusFold.radio(isOn: mesh.isOn, problem: mesh.problem, licensed: mesh.licensed, applying: mesh.applying,
                                        regionUnset: mesh.regionUnset, status: mesh.status, isMine: mesh.isMine,
                                        letGoByHand: mesh.letGoByHand))
    }

    var body: some View {
        let fold = fold
        Group {
            if fold.needsAttention {
                full(canFold: false)
            } else {
                // The folded line keeps its place and height; the open lines lie over it and over the top of
                // the messages, so opening or folding never resizes the list (which would scroll it).
                ZStack { if expanded { folded(fold).hidden() } else { folded(fold) } }
                    .overlay(alignment: .top) {
                        if expanded {
                            full(canFold: true)
                                .padding(.bottom, DLSpace.xs)
                                .background(Color.dlNight.padding(.horizontal, -DLSpace.md))
                                .overlay(alignment: .bottom) { Rectangle().fill(Color.dlHairline).frame(height: DLStroke.hair) }
                        }
                    }
            }
        }
        .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.sm)
    }

    private func toggle() {
        Haptics.tap()
        if reduceMotion { expanded.toggle() } else { withAnimation(DLMotion.move) { expanded.toggle() } }
    }

    // MARK: Folded

    private func folded(_ fold: ChatStatusFold) -> some View {
        HStack(alignment: .center, spacing: DLSpace.xs) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: DLSpace.xs) {
                    dot(fold.anyActive ? .dlGo : .dlSoft)
                    Text(fold.summary.uppercased()).dlCaps(.caption).foregroundStyle(Color.dlSoft)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down").font(.dl(.caption2, .semibold)).foregroundStyle(Color.dlSoft)
                }
                .frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fold.summary)
            .accessibilityHint("Shows relay and radio details")
            .accessibilityIdentifier("chat-status-summary")
            Spacer(minLength: DLSpace.xs)
            if !online.isOn { turnOnButton }
        }
        .transition(.opacity)
    }

    // MARK: Full

    private func full(canFold: Bool) -> some View {
        HStack(alignment: .top, spacing: DLSpace.xs) {
            VStack(alignment: .leading, spacing: 4) {
                relayLine
                if mesh.isOn { radioLine }
            }
            .contentShape(Rectangle())
            .onTapGesture { if canFold { toggle() } }
            if canFold {
                Button(action: toggle) {
                    Image(systemName: "chevron.up").font(.dl(.caption, .semibold)).foregroundStyle(Color.dlSoft)
                        .frame(width: 32, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fold status")
                .accessibilityIdentifier("chat-status-fold")
            }
        }
        .transition(.opacity)
    }

    private var relayLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DLSpace.xs) {
            dot(relayColor)
            Text(relayText.uppercased()).dlCaps(.caption).accessibilityLabel(relayText).foregroundStyle(online.torFailed && online.torOn ? Color.dlWarn : Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DLSpace.xs)
            if !online.isOn {
                turnOnButton
            } else if online.torOn, online.torFailed {
                Button("Try again") { Haptics.tap(); online.retryTor() }.font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlGo)
                    .frame(minHeight: DLSize.control).accessibilityIdentifier("tor-retry")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("online-status")
    }

    private var radioLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DLSpace.xs) {
            dot(mesh.isReady ? Color.dlGo : Color.dlSoft)
            let radioText = "Radio · " + (mesh.problem ?? MeshStatus.text(mesh))
            Text(radioText.uppercased()).dlCaps(.caption).accessibilityLabel(radioText)
                .foregroundStyle(mesh.problem != nil || mesh.licensed ? Color.dlWarn : Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("radio-status")
    }

    private var turnOnButton: some View {
        Button("Turn on") { Haptics.tap(); online.setEnabled(true) }.font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlGo)
            .frame(minHeight: DLSize.control).accessibilityIdentifier("online-turn-on")
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            .accessibilityHidden(true)
    }

    private var relayColor: Color {
        if online.isOn, online.torOn, online.torFailed { return .dlWarn }
        return online.isOn && online.connected > 0 ? .dlGo : .dlSoft
    }

    private var relayText: String {
        // Says which route this is (relays) and whether Tor carries it, so it reads apart from the radio line.
        guard online.isOn else { return "Relays · Online chat is off" }
        if online.torOn, online.torPort == nil {
            return online.torFailed ? "Relays · Tor could not connect. Nothing is sent online." : "Relays · connecting to Tor \(online.torProgress)%"
        }
        let route = online.torOn ? "via Tor" : "no Tor"
        switch online.connected {
        case 0: return "Relays · none reached yet · messages wait"
        case 1: return "Relays · 1 reached \(route)"
        default: return "Relays · \(online.connected) reached \(route)"
        }
    }
}
