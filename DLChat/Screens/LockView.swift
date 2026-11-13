import SwiftUI
import UIKit

/// Shown over everything while the app is locked, or while it has no PIN yet (then it asks for a new
/// one, typed twice, and cannot be skipped). A normal PIN and the duress PIN both end in the same unlock;
/// nothing here says which one was typed.
struct LockView: View {
    let lock: AppLock
    let wipe: () -> Bool
    @State private var digits = ""
    @State private var note = ""
    /// Create mode: the first entry, waiting to be typed again.
    @State private var firstEntry: String?
    /// Create mode: the PIN length the person picked.
    @State private var length = AppLock.defaultLength
    /// "Face ID" or "Touch ID", read once when the screen appears.
    @State private var biometryName = "Face ID"
    /// Locked with Face ID on: "Use PIN" was tapped on the cover, so the pad shows without waiting for Face ID.
    @State private var pinInstead = false
    /// Create mode: the new PIN, typed twice and matching, held while the person answers the Face ID question.
    /// It is saved only once they answer.
    @State private var offeringBiometrics: String?

    private var creating: Bool { lock.mustCreatePIN && !lock.isLocked }

    /// Locked with Face ID on, and Face ID has not answered yet (not asked yet this lock, or its sheet is up):
    /// a plain cover shows instead of the PIN pad, so a Face ID unlock never flashes the pad. Once Face ID
    /// says no (failed, cancelled, locked out, faces changed) this is false and the pad shows.
    private var waitingForBiometrics: Bool { Self.coverHidesPad(lock, pinInstead: pinInstead) }

    /// DEBUG `-hold-faceid`: Face ID is never asked on its own, so UI tests and screenshots can see the cover
    /// (the Simulator answers Face ID at once). Always false in release builds.
    static var holdsBiometrics: Bool {
        #if DEBUG
        LaunchSwitches.arguments.contains("-hold-faceid")
        #else
        false
        #endif
    }

    static func coverHidesPad(_ lock: AppLock, pinInstead: Bool) -> Bool {
        lock.isLocked && lock.biometricsOn && !pinInstead && (lock.biometricPromptOpen || !lock.biometricAskedThisLock)
    }

    private var title: String {
        guard creating else { return "Enter your PIN" }
        return firstEntry == nil ? "Create a PIN" : "Type it again"
    }
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            if waitingForBiometrics {
                biometricCover
            } else if let pin = offeringBiometrics {
                biometricOffer(pin)
            } else {
                pad
            }
        }
        .onAppear {
            LaunchTiming.mark("lock.appear")
            // Face ID first: reading the kind of biometry takes a moment and only changes a label.
            askForBiometrics()
            biometryName = lock.biometrics.kind ?? "Face ID"
        }
        // The lock screen goes up as DLChat leaves, so Face ID is asked for when it comes back, not then.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            askForBiometrics()
        }
    }

    /// What shows while Face ID is deciding: the same lock mark as the cover iOS sees when DLChat is not
    /// active, so nothing changes on screen until DLChat opens. The PIN is always one tap away.
    private var biometricCover: some View {
        ZStack {
            Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.6))
                .accessibilityLabel("DLChat is locked. Waiting for \(biometryName).")
                .accessibilityIdentifier("lock-cover")
            VStack {
                Spacer()
                Button("Use PIN") { Haptics.tap(); pinInstead = true }
                    .font(.dl(.headline)).foregroundStyle(Color.dlSoft)
                    .frame(maxWidth: .infinity, minHeight: DLSize.primary)
                    .accessibilityIdentifier("lock-use-pin")
            }
            .padding(DLSpace.md)
        }
    }

    /// First run, right after the PIN is typed twice: Face ID is offered once, here, so nobody has to find it
    /// in Safety. Either answer saves the PIN and opens DLChat; Safety keeps the switch.
    private func biometricOffer(_ pin: String) -> some View {
        ScrollView {
            VStack(spacing: DLSpace.md) {
                Image(systemName: biometryName == "Touch ID" ? "touchid" : biometryName == "Optic ID" ? "opticid" : "faceid")
                    .font(.system(size: 56)).foregroundStyle(Color.dlText).padding(.top, DLSpace.lg * 2)
                    .accessibilityHidden(true)
                Text("Unlock with \(biometryName)?").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("lock-biometrics-offer")
                Text("Open DLChat with \(biometryName) instead of typing your PIN each time. Your PIN still works, and DLChat asks for it if \(biometryName) fails.")
                    .font(.dl(.body)).foregroundStyle(Color.dlText).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Someone who \(biometryName == "Touch ID" ? "presses your finger to the phone" : "holds the phone up to your face") could open DLChat this way, so choose Not now if that could happen to you. You can change this any time in Settings > Safety.")
                    .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Unlock with \(biometryName)") { save(pin, biometrics: true) }
                    .buttonStyle(.dlPrimary).padding(.top, DLSpace.md).accessibilityIdentifier("lock-biometrics-yes")
                Button("Not now") { save(pin, biometrics: false) }
                    .buttonStyle(.dlSecondary).accessibilityIdentifier("lock-biometrics-not-now")
                // An older install may already hold groups, so wiping stays possible from here too.
                HoldToWipeButton(onWipe: wipe).padding(.top, DLSpace.md)
            }
            .padding(.horizontal, DLSpace.md)
        }
    }

    private var pad: some View {
            ScrollView {
                VStack(spacing: DLSpace.md) {
                    Text(title).font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                        .padding(.top, DLSpace.lg)
                        .accessibilityIdentifier("lock-title")
                    if creating && firstEntry == nil {
                        Text("DLChat asks for this PIN every time you open it. A forgotten PIN cannot be recovered: the only way back in is to wipe everything.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        DLSegments(selection: $length, options: AppLock.allowedLengths) { "\($0) digits" }
                        .accessibilityIdentifier("lock-length")
                        .onChange(of: length) { _, _ in digits = ""; note = "" }
                        if length == 4 {
                            Text("4 digits is quicker to type but easier to guess.")
                                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                        }
                    }
                    Text(digits.isEmpty ? "No digits yet" : String(repeating: "• ", count: digits.count))
                        .font(digits.isEmpty ? .dl(.headline) : .dlMono(.title, .bold)).foregroundStyle(digits.isEmpty ? Color.dlSoft : Color.dlText)
                        // The readout window, as on Send: what has been keyed in so far.
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.dlWell, in: RoundedRectangle.key)
                        .overlay { RoundedRectangle.key.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
                        .accessibilityLabel("\(digits.count) digits entered")
                        .accessibilityIdentifier("lock-digits")
                    if !creating && lock.biometricsInvalidated && note.isEmpty {
                        Text("\(biometryName) changed on this iPhone, so DLChat needs your PIN. Turn \(biometryName) on again in Safety.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("lock-biometrics-changed")
                    }
                    Text(note).font(.dl(.subheadline)).foregroundStyle(Color.dlWarn)
                        .frame(maxWidth: .infinity, minHeight: 20).multilineTextAlignment(.center)
                        .accessibilityIdentifier("lock-note")
                    VStack(spacing: DLSpace.sm) {
                        ForEach(rows, id: \.self) { row in
                            HStack(spacing: DLSpace.sm) { ForEach(row, id: \.self) { key($0) } }
                        }
                        HStack(spacing: DLSpace.sm) {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 64)
                            key("0")
                            Button { Haptics.tap(); if !digits.isEmpty { digits.removeLast() } } label: {
                                Image(systemName: "delete.left").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .background(Color.dlPanel, in: RoundedRectangle.key)
                                    .overlay { RoundedRectangle.key.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
                            }
                            .buttonStyle(.dlPress)
                            .accessibilityLabel("Delete last digit")
                        }
                    }
                    if creating {
                        Button(firstEntry == nil ? "Next" : "Save PIN", action: create).buttonStyle(.dlPrimary)
                            .disabled(digits.count != length).accessibilityIdentifier("lock-create")
                    } else {
                        Button("Unlock", action: submit).buttonStyle(.dlPrimary)
                            .disabled(digits.isEmpty).accessibilityIdentifier("lock-unlock")
                        if lock.biometricsOn {
                            Button {
                                Haptics.tap()
                                Task { await lock.unlockWithBiometrics() }
                            } label: {
                                Label("Unlock with \(biometryName)", systemImage: biometryName == "Touch ID" ? "touchid" : "faceid")
                            }
                            .buttonStyle(.dlSecondary).accessibilityIdentifier("lock-biometrics")
                        }
                    }
                    // Someone may only ever see this screen, so wiping must be possible from here.
                    HoldToWipeButton(onWipe: wipe).padding(.top, DLSpace.md)
                }
                .padding(.horizontal, DLSpace.md)
            }
    }

    /// Asks for Face ID on its own once per lock, only while DLChat is on screen. A cancel leaves the PIN pad
    /// (and the Face ID button) without asking again, even though the sheet closing makes the app active again.
    private func askForBiometrics() {
        guard UIApplication.shared.applicationState == .active, !Self.holdsBiometrics else { return }
        lock.askForBiometricsIfDue()
    }

    private func key(_ digit: String) -> some View {
        Button { Haptics.tap(); if digits.count < (creating ? length : 32) { digits.append(digit) } } label: {
            Text(digit).font(.dlMono(.title, .semibold)).foregroundStyle(Color.dlText)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .overlay { RoundedRectangle.key.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
        }
        .buttonStyle(.dlPress)
        .accessibilityLabel(digit)
    }

    private func create() {
        let typed = digits
        digits = ""
        guard let first = firstEntry else {
            if let problem = AppLock.check(typed) { note = problem.message; return }
            firstEntry = typed
            note = ""
            return
        }
        firstEntry = nil
        guard first == typed else {
            note = "Those did not match. Start again."
            Haptics.error()
            return
        }
        // This phone has Face ID (or Touch ID) set up: offer it before the PIN is saved and DLChat opens.
        if lock.biometrics.kind != nil {
            note = ""
            offeringBiometrics = typed
        } else {
            save(typed, biometrics: false)
        }
    }

    /// Saves the new PIN, which opens DLChat. With `biometrics`, Face ID is then turned on the same way
    /// Safety does it, with that PIN; if that fails DLChat still opens and Safety shows it as off.
    private func save(_ pin: String, biometrics: Bool) {
        offeringBiometrics = nil
        if let problem = lock.setPIN(pin) {
            note = problem.message
            Haptics.error()
        } else {
            note = ""
            if biometrics { _ = lock.turnOnBiometrics(pin: pin) }
            Haptics.success()
        }
    }

    private func submit() {
        let result = lock.enter(digits)
        digits = ""
        switch result {
        case .unlocked:
            note = ""
        case .wrong:
            note = "Wrong PIN."
            Haptics.error()
        case .wipeFailed:
            note = "Could not finish. Try again."
            Haptics.error()
        case .waiting(let seconds):
            note = "Too many wrong tries. Wait \(Self.format(seconds)) and try again."
            Haptics.error()
        }
    }

    private static func format(_ seconds: Int) -> String {
        seconds >= 120 ? "\((seconds + 59) / 60) minutes" : "\(seconds) seconds"
    }
}
