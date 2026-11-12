import UIKit
import UserNotifications

/// New-message alerts (owner decision 2026-11-08). Off until the person turns them on in Settings,
/// which is when iOS asks. The alert never names the group, the sender or a word of the message: the
/// lock screen shows only `text`. Posted only while DLChat is not on screen.
@MainActor
enum Notifier {
    /// The only text any DLChat notification shows, local or iCloud push.
    static let text = "DLChat has a notification available for you"
    static let enabledKey = "notify.enabled"
    private static let requestID = "dlchat-new-message"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: enabledKey) }

    /// Turns alerts on (asking iOS the first time) or off. Returns whether they are on afterwards.
    static func setOn(_ on: Bool, defaults: UserDefaults = .standard) async -> Bool {
        guard on else {
            defaults.set(false, forKey: enabledKey)
            clear()
            return false
        }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        defaults.set(granted, forKey: enabledKey)
        return granted
    }

    /// A new message was stored. One pending alert at most: a burst of messages replaces it.
    static func newMessage(defaults: UserDefaults = .standard) {
        guard isOn(defaults), UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.body = text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
    }

    /// Opening the app or a wipe removes alerts already on the lock screen.
    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    static func wipe(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: enabledKey)
        clear()
    }
}
