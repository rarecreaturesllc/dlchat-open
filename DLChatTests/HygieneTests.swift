import XCTest
import UIKit
@testable import DLChat

final class HygieneTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sources(under dirs: [String]) throws -> [(String, String)] {
        var found: [(String, String)] = []
        for dir in dirs {
            let url = root.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            for file in files where file.pathExtension == "swift" && !file.path.contains("/.build/") {
                found.append((file.path, try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return found
    }

    func testKeyboardExtensionsAreRefused() {
        XCTAssertFalse(Hygiene.allowsExtensionPoint(.keyboard))
        XCTAssertTrue(Hygiene.allowsExtensionPoint(UIApplication.ExtensionPointIdentifier(rawValue: "com.apple.widget-extension")))
    }

    @MainActor func testPlaintextCopyWritesTheText() {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        Hygiene.copyPlaintext("meet at the bridge", to: board)
        XCTAssertEqual(board.string, "meet at the bridge")
        XCTAssertEqual(board.items.count, 1)
    }

    @MainActor func testWipeClearsCopiedTextAndTheRadioNoticeFlag() throws {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "app.dlchat.tests.\(UUID().uuidString)"))
        RadioNotice.markSeen(defaults)
        Onboarding.markDone(defaults)
        Hygiene.copyPlaintext("meet at the bridge", to: board)
        Hygiene.clearAfterWipe(pasteboard: board, defaults: defaults)
        XCTAssertNil(board.string)
        XCTAssertFalse(RadioNotice.seen(defaults))
        XCTAssertFalse(Onboarding.done(defaults), "after a wipe, setup asks the group question again")
    }

    @MainActor func testWipeLeavesPasteboardTextThatIsNotOurs() throws {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "app.dlchat.tests.\(UUID().uuidString)"))
        Hygiene.copyPlaintext("ours", to: board)
        board.string = "copied from another app"
        Hygiene.clearAfterWipe(pasteboard: board, defaults: defaults)
        XCTAssertEqual(board.string, "copied from another app")
    }

    /// Autocorrect is on only in the Chat message boxes (owner decision 1C, 2026-11-09). Every other
    /// field and search bar keeps it off.
    func testAutocorrectIsOnlyInTheChatMessageBoxes() throws {
        let chatBoxes = ["chat-field", "mesh-field", "direct-field"]
        let all = try sources(under: ["DLChat/Screens", "DLChat/Shared"])
        XCTAssertFalse(all.isEmpty)
        var chat = Set<String>()
        for (path, text) in all {
            let lines = text.components(separatedBy: "\n")
            // UITextField() in ScreenShield is never shown or typed in.
            for (i, line) in lines.enumerated() where (line.contains("TextField(") && !line.contains("UITextField(")) || line.contains("TextEditor(") || line.contains("SecureField(") {
                let block = lines[i..<min(i + 10, lines.count)].joined(separator: "\n")
                if let id = chatBoxes.first(where: { block.contains("accessibilityIdentifier(\"\($0)\")") }), block.contains(".chatKeyboard()") {
                    chat.insert(id)
                    continue
                }
                let window = lines[i..<min(i + 6, lines.count)].joined(separator: "\n")
                XCTAssertTrue(window.contains("autocorrectionDisabled()"), "\(path):\(i + 1) leaves autocorrect on")
            }
            // A search bar autocorrects unless told not to.
            for (i, line) in lines.enumerated() where line.contains(".searchable(") {
                let window = lines[i..<min(i + 3, lines.count)].joined(separator: "\n")
                XCTAssertTrue(window.contains("autocorrectionDisabled()"), "\(path):\(i + 1) search leaves autocorrect on")
            }
            for (i, line) in lines.enumerated() where line.contains("autocorrectionDisabled(false)") {
                XCTAssertTrue(path.hasSuffix("DLChat/Shared/KeyboardPrivacy.swift"), "\(path):\(i + 1) turns autocorrect on outside chatKeyboard()")
            }
        }
        XCTAssertEqual(chat, Set(chatBoxes), "every Chat message box autocorrects")
    }

    /// Exact strings and secrets never autocorrect: a "fix" would corrupt
    /// them, and the keyboard would learn the phrase or a PIN.
    func testSecretAndExactFieldsNeverAutocorrect() throws {
        let ids = ["join-phrase", "backup-check-field", "picture-password-slot-", "word-field", "paste-field",
                   "practice-field", "group-room-field", "settings-relay-field", "safety-\\("]
        let all = try sources(under: ["DLChat/Screens", "DLChat/Shared"])
        var seen = Set<String>()
        for (path, text) in all {
            let lines = text.components(separatedBy: "\n")
            for id in ids {
                for (i, line) in lines.enumerated() where line.contains("accessibilityIdentifier(\"\(id)") {
                    guard let start = lines[..<i].lastIndex(where: { $0.contains("TextField(") || $0.contains("SecureField(") }) else { continue }
                    let block = lines[start...i].joined(separator: "\n")
                    XCTAssertTrue(block.contains("autocorrectionDisabled()"), "\(path): \(id) must keep autocorrect off")
                    XCTAssertFalse(block.contains(".chatKeyboard("), "\(path): \(id) must not autocorrect")
                    seen.insert(id)
                }
            }
        }
        XCTAssertEqual(seen, Set(ids), "every exact-string field was found")
    }

    /// Notifications show one fixed sentence, never a group, sender or message text (owner decision 2026-11-08).
    @MainActor func testNotificationsCarryNoMessageContent() throws {
        XCTAssertEqual(Notifier.text, "DLChat has a notification available for you")
        let all = try sources(under: ["DLChat"])
        // Only files that build notification content (local or iCloud push); map pins also have titles.
        for (path, text) in all where text.contains("UNMutableNotification" + "Content") || text.contains("Notification" + "Info()") {
            for setter in [".body =", ".title =", ".subtitle =", ".alertBody =", ".title" + "LocalizationKey", ".alert" + "LocalizationKey"] where text.contains(setter) {
                for line in text.split(separator: "\n") where line.contains(setter) {
                    XCTAssertTrue(line.contains("Notifier.text") || (path.hasSuffix("DLChat/Shared/Notifier.swift") && line.contains("= text")),
                                  "\(path): notification text must be Notifier.text: \(line)")
                }
            }
        }
    }

    @MainActor func testWipeTurnsNotificationsOff() {
        let defaults = UserDefaults(suiteName: "notify-wipe-test")!
        defaults.set(true, forKey: Notifier.enabledKey)
        Notifier.wipe(defaults)
        XCTAssertFalse(Notifier.isOn(defaults))
        defaults.removePersistentDomain(forName: "notify-wipe-test")
    }

    func testNoNetworkAPIsInAppOrCore() throws {
        // Names are split so this file does not match its own scan.
        let banned = ["URL" + "Session", "NW" + "Connection", "NW" + "Listener", "CF" + "Socket", "CFStream" + "CreatePair",
                      "WK" + "WebView", "Multipeer" + "Connectivity", "NSURL" + "Connection", "CK" + "Container",
                      "CBCentral" + "Manager", "MLN" + "MapView", "MLN" + "NetworkConfiguration"]
        let all = try sources(under: ["DLChat", "Packages/DLCore/Sources", "Packages/TorKit/Sources"])
        XCTAssertGreaterThan(all.count, 10)
        for (path, text) in all {
            for name in banned {
                // Online chat (owner decision 2026-11-07) is the one deliberate internet use: relay
                // sockets, only inside the relay pool. Network code anywhere else still fails.
                if name == "URL" + "Session", path.hasSuffix("DLChat/Online/RelayPool.swift") { continue }
                // The iCloud mailbox (same decision) is the only CloudKit use, inside its own file.
                if name == "CK" + "Container", path.hasSuffix("DLChat/Online/CloudCarrier.swift") { continue }
                // The Meshtastic radio (owner decision 2026-11-08) is the only Bluetooth use, inside its link.
                if name.hasPrefix("CBCentral"), path.hasSuffix("DLChat/Meshtastic/MeshtasticLink.swift") { continue }
                // The street map (owner decision 2026-11-08) is the only MapLibre use; it is built only with Tor's port.
                if name.hasPrefix("MLN"), path.hasSuffix("DLChat/Screens/MeshStreetMap.swift") { continue }
                XCTAssertFalse(text.contains(name), "\(path) uses \(name)")
            }
        }
    }

    /// Screenshots of the app come out blank: a shown window's layer sits inside a secure text field's
    /// layer, in the window's old place, and goes back there when released.
    @MainActor func testScreenShieldWrapsAndReleasesAWindow() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 5
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { ScreenShield.release(window); window.isHidden = true }
        let host = try XCTUnwrap(window.layer.superlayer, "a shown window has a scene layer above it")
        let place = try XCTUnwrap(host.sublayers?.firstIndex(of: window.layer))

        ScreenShield.protect(window)
        XCTAssertTrue(ScreenShield.isProtected(window))
        let secure = try XCTUnwrap(window.layer.superlayer)
        XCTAssertTrue(secure.superlayer === host)
        XCTAssertEqual(host.sublayers?.firstIndex(of: secure), place, "keeps the window's place among the windows")
        ScreenShield.protect(window)
        XCTAssertTrue(window.layer.superlayer === secure, "protecting twice changes nothing")

        ScreenShield.release(window)
        XCTAssertFalse(ScreenShield.isProtected(window))
        XCTAssertTrue(window.layer.superlayer === host)
        XCTAssertEqual(host.sublayers?.firstIndex(of: window.layer), place)
        XCTAssertNil(secure.superlayer)
    }

    /// The app's own window is shielded once it is on screen (the test host launches without `-seed-demo`).
    @MainActor func testAppWindowIsShielded() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let main = try XCTUnwrap(scene.windows.first { $0.windowLevel == .normal })
        ScreenShield.protectAppWindows()
        XCTAssertTrue(ScreenShield.isProtected(main))
    }
}
