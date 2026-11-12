import CryptoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Device hygiene: what the app does so plaintext and secrets leave as little trace as possible.
enum Hygiene {
    /// Decrypted text stays on this phone (no Universal Clipboard) and expires.
    static let pasteboardLifetime: TimeInterval = 60

    /// Digest of the last text this app copied, so a wipe can tell whether the pasteboard still holds it.
    @MainActor private static var lastCopied: Data?

    private static func digest(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }

    @MainActor static func copyPlaintext(_ text: String, to pasteboard: UIPasteboard = .general, now: Date = Date()) {
        lastCopied = digest(text)
        pasteboard.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: now.addingTimeInterval(pasteboardLifetime)])
    }

    /// Wipe: removes the text this app copied, if it is still on the pasteboard, forgets the radio-rules notice
    /// and the old autocorrect switch (removed; owner decision 1C).
    @MainActor static func clearAfterWipe(pasteboard: UIPasteboard = .general, defaults: UserDefaults = .standard) {
        if let copied = lastCopied, let text = pasteboard.string, digest(text) == copied { pasteboard.items = [] }
        lastCopied = nil
        RadioNotice.reset(defaults)
        defaults.removeObject(forKey: "keyboard.autocorrect")
        Onboarding.reset(defaults)
    }

    /// Files Send writes to the temporary folder for sharing. Normally removed when their screen closes;
    /// a crash or kill skips that, so every launch removes them too.
    static let leftoverFiles = [SoundFile.fileName, "DLChat invite.png"]

    /// At launch: removes what a crash or kill left from Send in the temporary folder.
    static func removeLeftoverFiles(in folder: URL = FileManager.default.temporaryDirectory) {
        for name in leftoverFiles { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
    }

    /// True while the screen is being recorded, mirrored or shared (AirPlay, QuickTime, screen recording).
    /// Screenshots and recordings already come out blank (see `ScreenShield`); the cover is a second line.
    @MainActor static var screenIsCaptured: Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .contains { $0.traitCollection.sceneCaptureState == .active }
    }

    /// Extension points the app refuses. Custom keyboards would see every letter typed.
    static func allowsExtensionPoint(_ identifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        identifier != .keyboard
    }
}

final class HygieneAppDelegate: NSObject, UIApplicationDelegate {
    /// Set by OnlineModel: fetches the iCloud mailboxes and says whether anything new arrived.
    @MainActor static var onPush: (() async -> Bool)?

    /// iCloud push (a CloudKit subscription fired): fetch the mailboxes before answering, so iOS does
    /// not suspend the app mid-fetch. The notification itself carries no text, so userInfo is not read.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in completionHandler(await Self.handlePush() ? .newData : .noData) }
    }

    @MainActor private static func handlePush() async -> Bool { await onPush?() ?? false }

    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        Hygiene.allowsExtensionPoint(extensionPointIdentifier)
    }
}

/// Keeps DLChat's windows out of screenshots and screen recordings: they come out blank.
///
/// iOS has no public switch for this. The one public route is the layer a secure text field (a password
/// field) draws into: iOS leaves that layer out of every screenshot, recording, AirPlay mirror and app
/// switcher snapshot. Each window's layer is moved inside such a layer, so everything the window shows,
/// sheets, menus and alerts included, is left out. Touches, VoiceOver and layout are untouched: only
/// the layer tree changes, never the views.
///
/// What it cannot stop: a photo of the screen taken with another camera, and the system keyboard, which
/// iOS draws itself. If a future iOS changes the password field, the shield quietly stops working; the
/// privacy cover (see `PrivacyCoverWindow`) still hides the app while the screen is recorded or shared.
@MainActor final class ScreenShield {
    private weak var window: UIWindow?
    private let field = UITextField()
    private var canvas: UIView?
    private var secure: CALayer? { canvas?.layer }

    private static var shields: [ObjectIdentifier: ScreenShield] = [:]

    private init(_ window: UIWindow) {
        self.window = window
        field.isSecureTextEntry = true
    }

    /// Demo screenshots for the App Store and the screenshot tests: off only in debug builds with `-seed-demo`.
    static var isOff: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-seed-demo") && !ProcessInfo.processInfo.arguments.contains("-shield-screenshots")
        #else
        false
        #endif
    }

    /// Shields `window`. Safe to call again at any time: it re-shields a window iOS has re-attached.
    static func protect(_ window: UIWindow) {
        guard !isOff else { return }
        shields = shields.filter { $0.value.window != nil }
        let shield = shields[ObjectIdentifier(window)] ?? ScreenShield(window)
        shields[ObjectIdentifier(window)] = shield
        shield.apply()
    }

    /// Puts the window's layer back where it was. Call before hiding a window for good.
    static func release(_ window: UIWindow) {
        shields.removeValue(forKey: ObjectIdentifier(window))?.remove()
    }

    /// Shields every normal-level window of the app (the one SwiftUI shows everything in).
    static func protectAppWindows() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.windowLevel == .normal { protect(window) }
        }
    }

    /// True while the window's layer sits inside the secure layer.
    static func isProtected(_ window: UIWindow) -> Bool {
        guard let shield = shields[ObjectIdentifier(window)] else { return false }
        return shield.secure != nil && window.layer.superlayer === shield.secure
    }

    private func apply() {
        guard let window, let host = window.layer.superlayer else { return }
        if let secure, host === secure { return }
        guard let view = canvas ?? Self.secureCanvas(of: field) else { return }
        canvas = view
        let canvas = view.layer
        canvas.removeFromSuperlayer()
        canvas.frame = host.bounds
        canvas.zPosition = window.layer.zPosition
        let index = host.sublayers?.firstIndex(of: window.layer) ?? host.sublayers?.count ?? 0
        host.insertSublayer(canvas, at: UInt32(index))
        canvas.addSublayer(window.layer)
    }

    private func remove() {
        guard let secure else { return }
        if let window, window.layer.superlayer === secure, let host = secure.superlayer {
            let index = host.sublayers?.firstIndex(of: secure) ?? host.sublayers?.count ?? 0
            host.insertSublayer(window.layer, at: UInt32(index))
        }
        secure.removeFromSuperlayer()
        canvas = nil
    }

    /// The view a secure text field draws its text in, taken out of the field. Its layer stays secure.
    private static func secureCanvas(of field: UITextField) -> UIView? {
        field.layoutIfNeeded()
        let canvas = field.subviews.first { String(describing: type(of: $0)).contains("CanvasView") } ?? field.subviews.first
        guard let canvas else { return nil }
        canvas.removeFromSuperview()
        canvas.isUserInteractionEnabled = false
        canvas.isAccessibilityElement = false
        return canvas
    }
}

/// Puts `PrivacyCover` in its own window above everything, sheets and full-screen covers included.
@MainActor enum PrivacyCoverWindow {
    private static var window: UIWindow?

    static func set(visible: Bool) {
        if !visible { window?.isHidden = true; window = nil; return }
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        cover.rootViewController = UIHostingController(rootView: PrivacyCover())
        cover.isHidden = false
        window = cover
    }
}

/// Puts `LockView` in its own window above every sheet and full-screen cover (but below the privacy cover),
/// so nothing presented over the main window can stay reachable while the app is locked.
@MainActor enum LockWindow {
    private static var window: UIWindow?
    private static weak var previous: UIWindow?

    static func set(visible: Bool, lock: AppLock, wipe: @escaping () -> Bool) {
        if !visible {
            if let window { ScreenShield.release(window) }
            window?.isHidden = true
            window = nil
            previous?.makeKey()
            previous = nil
            return
        }
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        previous = scene.windows.first { $0.isKeyWindow }
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert
        let host = UIHostingController(rootView: LockView(lock: lock, wipe: wipe).preferredColorScheme(.dark).tint(Color.dlGo))
        host.view.backgroundColor = UIColor(Color.dlNight)
        host.view.accessibilityViewIsModal = true
        cover.rootViewController = host
        cover.makeKeyAndVisible()
        ScreenShield.protect(cover)
        window = cover
    }
}

/// Opaque screen shown whenever the app is not active, so the app switcher snapshot is blank, and while
/// the screen is recorded or mirrored.
struct PrivacyCover: View {
    let captured = Hygiene.screenIsCaptured
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.6))
                if captured {
                    Text("Hidden while the screen is recorded or shared").font(.headline)
                        .foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("privacy-cover")
    }
}
