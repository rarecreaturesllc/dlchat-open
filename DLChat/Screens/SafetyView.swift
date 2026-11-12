import SwiftUI

/// The shield sheet on the screens that cover the main one (the words read out, the QR code, the tones):
/// panic wipe and the lock, without going back first. On the main screen the same `SafetySection`
/// sits at the top of `SettingsView`.
struct SafetyView: View {
    let lock: AppLock
    let wipe: () -> Bool
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text("Safety").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    SafetySection(lock: lock, wipe: wipe, close: done)
                }
                .padding(DLSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .tint(Color.dlGo)
    }
}

/// Panic wipe, the pressure mark, and the lock (PIN, Face ID, duress PIN). The wipe comes first; the
/// rarely used lock settings are folded so the section stays short.
struct SafetySection: View {
    let lock: AppLock
    /// The compose model, when opened over the main screen; it owns the pressure mark.
    var compose: ComposeModel?
    let wipe: () -> Bool
    /// Closes the sheet this sits in, after a finished wipe.
    let close: () -> Void
    @State private var pin = ""
    @State private var pinAgain = ""
    @State private var duress = ""
    @State private var biometricPIN = ""
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.md) {
            HoldToWipeButton { let ok = wipe(); if ok { close() }; return ok }
            small("Erases every group, phrase and message on this phone. It cannot be undone, so keep your phrase on paper.")
                .accessibilityIdentifier("safety-wipe-note")

            if let compose {
                Toggle("Mark my next message as sent under pressure", isOn: Bindable(compose).duress)
                    .font(.dl(.body)).foregroundStyle(Color.dlText)
                    .frame(minHeight: DLSize.control)
                    .accessibilityIdentifier("safety-pressure")
                small("The people who read it are warned to treat it with care. Nothing shows on your screen. It clears after you send.")
            }

            if lock.hasPIN {
                SettingsFold(title: "Change PIN", id: "safety-fold-pin") {
                    small("DLChat asks for your PIN every time you open it. The PIN cannot be turned off, only changed. A new PIN can be 4, 6 or 8 digits.")
                        .accessibilityIdentifier("safety-pin-about")
                    field("New PIN", text: $pin)
                    field("New PIN again", text: $pinAgain)
                    Button("Change PIN") {
                        // Typed twice: a mistyped new PIN would lock the person out, with only the wipe as a way back.
                        note = pin != pinAgain ? "The two PINs did not match." : lock.setPIN(pin)?.message ?? "PIN changed."
                        pin = ""; pinAgain = ""; focused = false
                    }
                    .buttonStyle(.dlSecondary).disabled(pin.isEmpty || pinAgain.isEmpty)
                    .accessibilityIdentifier("safety-change-pin")
                }
                biometricsFold
                // Never says whether one is set: the stored data looks the same either way.
                SettingsFold(title: "Duress PIN", id: "safety-fold-duress") {
                    small("Typing this PIN on the lock screen erases everything and opens an empty app that looks normal. The phone's stored data looks the same with or without one, so this screen never says whether one is set. Saving a new one replaces any earlier one.")
                        .accessibilityIdentifier("safety-duress-about")
                    field("Duress PIN", text: $duress)
                    Button("Set duress PIN") {
                        note = lock.setDuressPIN(duress)?.message ?? "Duress PIN saved."
                        duress = ""; focused = false
                    }
                    .buttonStyle(.dlSecondary).disabled(duress.isEmpty)
                }
            } else {
                // Only right after a wipe: the app asks for a new PIN the next time it is opened, or here.
                small("Set a PIN of 4, 6 or 8 digits. DLChat asks for it every time you open it. There is no way to recover a forgotten PIN except the wipe.")
                    .accessibilityIdentifier("safety-pin-about")
                field("New PIN", text: $pin)
                field("New PIN again", text: $pinAgain)
                Button("Set PIN") {
                    note = pin != pinAgain ? "The two PINs did not match." : lock.setPIN(pin)?.message ?? "PIN set."
                    pin = ""; pinAgain = ""; focused = false
                }
                .buttonStyle(.dlPrimary).disabled(pin.isEmpty || pinAgain.isEmpty)
            }
            if !note.isEmpty {
                Text(note).font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlText)
                    .accessibilityIdentifier("safety-note")
            }
        }
        .contentShape(Rectangle()).onTapGesture { focused = false }
    }

    /// Face ID unlock: off until turned on here with the PIN. The fold's summary says whether it is on.
    private var biometricsFold: some View {
        let name = lock.biometrics.kind ?? "Face ID"
        return SettingsFold(title: name, summary: lock.biometricsOn ? "On" : "Off", id: "safety-fold-biometrics") {
            small("Open DLChat with \(name) instead of typing your PIN. The PIN still works and is asked for again if \(name) fails or the faces on this iPhone change. Someone who holds the phone up to your face can open DLChat this way, and \(name) never erases anything, so leave it off if that could happen to you; only the typed duress PIN wipes.")
            if lock.biometricsOn {
                Button("Turn off \(name)") {
                    lock.turnOffBiometrics()
                    note = "\(name) is off. DLChat asks for your PIN."
                }
                .buttonStyle(.dlSecondary).accessibilityIdentifier("safety-biometrics-off")
            } else {
                field("Your PIN", text: $biometricPIN)
                Button("Turn on \(name)") {
                    let result = lock.turnOnBiometrics(pin: biometricPIN)
                    note = result == .on ? "\(name) is on." : result.message.replacingOccurrences(of: "Face ID", with: name)
                    biometricPIN = ""; focused = false
                }
                .buttonStyle(.dlSecondary).disabled(biometricPIN.isEmpty)
                .accessibilityIdentifier("safety-biometrics-on")
            }
        }
    }

    private func small(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .keyboardType(.numberPad).textContentType(.none).autocorrectionDisabled()
            .focused($focused).dlField(focused: focused)
            .accessibilityIdentifier("safety-\(title)")
    }
}

/// A row that shows or hides the rarely used part of a section, so Settings stays short.
/// Closed by default; the optional summary (such as "On") shows the state without opening it.
struct SettingsFold<Content: View>: View {
    let title: String
    var summary: String?
    let id: String
    let content: Content
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, summary: String? = nil, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.id = id
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            Button {
                Haptics.tap()
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: DLSpace.xs) {
                    Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: DLSpace.xs)
                    // The state as a legend, like a switch position printed on the panel.
                    if let summary { Text(summary.uppercased()).dlCaps(.footnote).foregroundStyle(Color.dlSoft) }
                    Image(systemName: "chevron.right").font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlSoft)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DLSize.control).contentShape(Rectangle())
                .overlay(alignment: .bottom) { Rectangle().fill(Color.dlHairline).frame(height: DLStroke.hair) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary.map { "\(title), \($0)" } ?? title)
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            .accessibilityIdentifier(id)
            if open { content }
        }
    }
}

/// A row that opens another screen: the title, an optional state, and a chevron.
struct SettingsLink: View {
    let title: String
    var detail: String?
    let id: String
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: DLSpace.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.dl(.body)).foregroundStyle(Color.dlText).multilineTextAlignment(.leading)
                    if let detail { Text(detail).font(.dl(.footnote)).foregroundStyle(Color.dlSoft) }
                }
                Spacer(minLength: DLSpace.xs)
                Image(systemName: "chevron.right").foregroundStyle(Color.dlSoft).accessibilityHidden(true)
            }
            // Room above the rule, so a two-line row's detail never sits on it.
            .padding(.vertical, DLSpace.xs)
            .frame(minHeight: DLSize.control).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color.dlHairline).frame(height: DLStroke.hair) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// The shield button that opens `SafetyView` on screens that cover the main one. Never one tap to wipe.
struct SafetyButton: View {
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Image(systemName: "shield.lefthalf.filled").font(.dl(.title3, .semibold)).foregroundStyle(Color.dlText)
                .frame(width: DLSize.control, height: DLSize.control)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .overlay { if contrast == .increased { RoundedRectangle.key.stroke(Color.dlSoft, lineWidth: 2) } }
        }
        .buttonStyle(.dlPress)
        .accessibilityLabel("Safety and wipe")
        .accessibilityIdentifier("safety-button")
    }
}

/// Locks the app at once.
struct LockNowButton: View {
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            Image(systemName: "lock.fill").font(.dl(.title3, .semibold)).foregroundStyle(Color.dlText)
                .frame(width: DLSize.control, height: DLSize.control)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .overlay { if contrast == .increased { RoundedRectangle.key.stroke(Color.dlSoft, lineWidth: 2) } }
        }
        .buttonStyle(.dlPress)
        .accessibilityLabel("Lock now")
        .accessibilityIdentifier("lock-now")
    }
}
