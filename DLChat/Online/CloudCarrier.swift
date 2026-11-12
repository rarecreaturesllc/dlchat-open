import CloudKit
import DLCore
import Foundation
import UserNotifications

/// The iCloud mailbox (second carrier, owner decision 2026-11-07): the same signed, sealed Nostr
/// event, stored as a record in DLChat's public CloudKit database under the day's mailbox key. Its
/// point is push: a query subscription lets iCloud wake the phone with a content-free notification,
/// which Nostr relays cannot do. Apple sees which iCloud account posted and when, never the text.
@MainActor
final class CloudCarrier {
    static let containerID = "iCloud.com.harrisonfischberg.dlchat"
    /// False until the owner has created the iCloud container, refreshed signing and deployed the
    /// schema (docs/icloud-setup.md). Then: set true, add CODE_SIGN_ENTITLEMENTS = Config/DLChat.entitlements
    /// and UIBackgroundModes remote-notification. While false nothing here touches CloudKit, which
    /// would crash without the entitlement.
    static let isConfigured = false
    static let recordType = "DLFrame"
    static let subscriptionID = "dlchat-mailboxes"

    var onEvent: ((Online.Event) -> Void)?
    private(set) var available = false

    private let defaults: UserDefaults
    private lazy var database = CKContainer(identifier: Self.containerID).publicCloudDatabase
    static let ownKey = "online.cloud.own", syncKey = "online.cloud.lastSync"

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Checks the iCloud account; without one the carrier stays off and Nostr carries everything.
    func start() async {
        available = (try? await CKContainer(identifier: Self.containerID).accountStatus()) == .available
    }

    // MARK: Send

    func send(_ event: Online.Event, mailbox: String) async -> Bool {
        guard available, let data = try? JSONSerialization.data(withJSONObject: event.json) else { return false }
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: event.id))
        record["mailbox"] = mailbox
        record["event"] = data
        record["expires"] = Date().addingTimeInterval(Online.lifetime)
        do {
            _ = try await database.save(record)
            var own = defaults.dictionary(forKey: Self.ownKey) as? [String: Date] ?? [:]
            own[event.id] = Date().addingTimeInterval(Online.lifetime)
            defaults.set(own, forKey: Self.ownKey)
            return true
        } catch {
            return false
        }
    }

    // MARK: Receive

    /// Fetches events for these mailboxes posted since the last look. Returns how many were read.
    @discardableResult
    func fetch(mailboxes: [String]) async -> Int {
        guard available, !mailboxes.isEmpty else { return 0 }
        let since = defaults.object(forKey: Self.syncKey) as? Date ?? Date().addingTimeInterval(-Online.lifetime)
        let predicate = NSPredicate(format: "mailbox IN %@ AND creationDate > %@", mailboxes, since.addingTimeInterval(-600) as NSDate)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        let started = Date()
        guard let (results, _) = try? await database.records(matching: query, resultsLimit: 200) else { return 0 }
        var count = 0
        for case (_, .success(let record)) in results {
            guard let data = record["event"] as? Data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = Online.Event(json: json) else { continue }
            onEvent?(event)
            count += 1
        }
        defaults.set(started, forKey: Self.syncKey)
        return count
    }

    /// One subscription for every watched mailbox; replaced as the days roll over. The notification
    /// says only that something arrived.
    func subscribe(mailboxes: [String]) async {
        guard available, !mailboxes.isEmpty else { return }
        let subscription = CKQuerySubscription(recordType: Self.recordType,
                                               predicate: NSPredicate(format: "mailbox IN %@", mailboxes),
                                               subscriptionID: Self.subscriptionID, options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.alertBody = Notifier.text
        info.soundName = "default"
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    /// Our own records past their lifetime: CloudKit has no expiry, so the sender deletes them.
    func deleteExpired() async {
        guard available else { return }
        var own = defaults.dictionary(forKey: Self.ownKey) as? [String: Date] ?? [:]
        let due = own.filter { $0.value < Date() }.map { CKRecord.ID(recordName: $0.key) }
        guard !due.isEmpty else { return }
        if (try? await database.modifyRecords(saving: [], deleting: due)) != nil {
            due.forEach { own[$0.recordName] = nil }
            defaults.set(own, forKey: Self.ownKey)
        }
    }

    /// Wipe: stop push and delete every record of ours that is still up (best effort, needs network).
    func wipe() async {
        let own = (defaults.dictionary(forKey: Self.ownKey) as? [String: Date] ?? [:]).keys.map { CKRecord.ID(recordName: $0) }
        if available {
            _ = try? await database.modifySubscriptions(saving: [], deleting: [Self.subscriptionID])
            if !own.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: own) }
        }
        [Self.ownKey, Self.syncKey].forEach(defaults.removeObject(forKey:))
    }

    /// Asked only when the person turns iCloud push on.
    static func askForNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
