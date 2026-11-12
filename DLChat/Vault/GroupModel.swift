import DLCore
import Foundation
import Observation

struct KeySet {
    let groupID: UUID
    let groupName: String
    let room: String
    let keys: Keys
}

/// App-level group state for the UI. Key derivation runs off the main actor.
@MainActor
@Observable
final class GroupModel {
    private(set) var groups: [ChatGroup] = []
    private(set) var loadFailed = false

    private(set) var wipeFailed = false
    /// Counts finished wipes, so screens left open behind the lock can close.
    private(set) var wipes = 0
    /// Bumped when a chat message is stored, so the chat screen reloads.
    var chatVersion = 0
    private(set) var activeID: UUID?
    /// Groups this phone has read receipts on for (cached: each store read decrypts the file).
    private(set) var receiptGroups: Set<UUID> = []

    /// The group Send, History and rooms follow: the chosen one, else the first in the list.
    var activeGroup: ChatGroup? { groups.first { $0.id == activeID } ?? groups.first }

    let vault: Vault
    private let book: GroupBook
    /// Unsent Send text per group (`nil` key: no group yet). Memory only: a crash, kill or relaunch
    /// leaves no draft behind (the owner's rule: nothing from Send or Receive survives the app closing).
    @ObservationIgnored private var drafts: [UUID?: String] = [:]
    /// The key sets for `groups` as last read, see `keySets()`. Dropped on every `reload()`, so on a wipe too.
    @ObservationIgnored private var keySetCache: (groups: [ChatGroup], sets: [KeySet])?

    init(vault: Vault = Vault()) {
        self.vault = vault
        book = GroupBook(vault: vault)
        // Builds up to 15 saved drafts in the store; erase any left there.
        try? book.dropDrafts()
        reload()
    }

    /// Panic wipe: the store key goes first, then every Keychain item and the store file. Callers
    /// reset any screen state that holds plaintext before calling this.
    @discardableResult
    func wipeEverything() -> Bool {
        book.dropCache()
        do {
            try vault.wipe()
            wipeFailed = false
            wipes += 1
        } catch {
            wipeFailed = true
        }
        retention = .standard
        drafts = [:]
        reload()
        return !wipeFailed
    }

    func reload() {
        keySetCache = nil
        do {
            groups = try book.groups()
            activeID = try book.activeGroupID()
            callSign = try book.callSign()
            receiptGroups = try book.receiptGroups()
            loadFailed = false
        } catch {
            groups = []
            activeID = nil
            callSign = nil
            receiptGroups = []
            loadFailed = true
        }
    }

    func prepareNew(words: Int) async throws -> PreparedGroup {
        let phrase = try Phrase.generate(words: words)
        return await Task.detached { PreparedGroup(phrase: phrase) }.value
    }

    func prepareJoin(_ text: String) async -> Result<PreparedGroup, JoinProblem> {
        switch GroupBook.parse(text) {
        case .failure(let problem):
            return .failure(problem)
        case .success(let phrase):
            return .success(await Task.detached { PreparedGroup(phrase: phrase) }.value)
        }
    }

    func keys(for group: ChatGroup, room: String = "") throws -> Keys? {
        try book.keys(for: group, room: room)
    }

    /// Every key set a received message could belong to: each group's default room, then its named rooms.
    /// Order matches `Receiver`'s `keysIndex`.
    func keySets() -> [KeySet] {
        if let keySetCache, keySetCache.groups == groups { return keySetCache.sets }
        var out: [KeySet] = []
        var wanted = 0
        for group in groups {
            for room in [""] + group.rooms {
                wanted += 1
                if let keys = try? book.keys(for: group, room: room) {
                    out.append(KeySet(groupID: group.id, groupName: group.name, room: room, keys: keys))
                }
            }
        }
        // Every received message asks for these, and each ask was several Keychain reads. Kept only when
        // complete: a locked iPhone reads none, and that must not be remembered as "no keys".
        if out.count == wanted { keySetCache = (groups, out) }
        return out
    }

    // MARK: Group list

    func setActive(_ group: ChatGroup) {
        try? book.setActive(group.id)
        reload()
    }

    func move(from source: IndexSet, to destination: Int) {
        try? book.moveGroups(from: source, to: destination)
        reload()
    }

    /// Returns false when the group's keys could not be deleted; the group is then still listed.
    @discardableResult
    func remove(_ group: ChatGroup) -> Bool {
        defer { reload() }
        do { try book.removeGroup(group); drafts[group.id] = nil; return true } catch { return false }
    }

    func deleteMessage(_ message: StoredMessage) {
        try? book.deleteMessage(id: message.id)
        chatVersion += 1  // Chat reloads, so a bubble deleted there disappears at once
    }

    func phrase(of group: ChatGroup) -> String? { (try? book.phraseText(for: group)) ?? nil }

    func safetyWords(of group: ChatGroup) -> [String] { ((try? book.keys(for: group)) ?? nil)?.safetyWords ?? [] }

    func draft(for groupID: UUID?) -> String { drafts[groupID] ?? "" }

    /// Keeps the draft in memory only; nothing is written to the store.
    func setDraft(_ text: String, for groupID: UUID?) throws {
        drafts[groupID] = text.isEmpty ? nil : text
    }

    // MARK: Rooms, received messages, retention

    func addRoom(_ name: String, to group: ChatGroup) {
        _ = try? book.addRoom(name, to: group)
        reload()
    }

    private(set) var retention = Retention.standard

    /// What friends see on this phone's Chat messages (Settings > Call sign). Sealed inside each message.
    private(set) var callSign: CallSign?

    func setCallSign(_ value: CallSign?) {
        try? book.setCallSign(value)
        callSign = value
    }

    func loadRetention() { retention = (try? book.retention()) ?? .standard }

    func setRetention(_ value: Retention) {
        try? book.setRetention(value)
        retention = value
    }

    /// `opened`: decrypted in Receive. Only its fingerprint is kept (for "Already received"), never its words.
    /// `chat`: arrived by a chat carrier, so read receipts may report it.
    func record(_ message: ReadMessage, from keySet: KeySet, opened: Bool = false, chat: Bool = false) -> RecordResult {
        guard let group = groups.first(where: { $0.id == keySet.groupID }) else { return .new }
        defer { chatVersion += 1 }
        return (try? book.record(message, group: group, room: keySet.room, opened: opened, chat: chat)) ?? .new
    }

    /// Whether "Decrypted" was already posted for this message decrypted in Receive.
    func isAcknowledged(_ message: ReadMessage, from keySet: KeySet) -> Bool {
        (try? book.isAcknowledged(id: StoredMessage.identity(of: message, groupID: keySet.groupID, room: keySet.room))) ?? false
    }

    func markAcknowledged(_ message: ReadMessage, from keySet: KeySet) {
        try? book.markAcknowledged(id: StoredMessage.identity(of: message, groupID: keySet.groupID, room: keySet.room))
    }

    /// A message that came in by a chat carrier (relays, radio). Nil when it could not be saved (the store
    /// cannot be read while the iPhone is locked), so the caller keeps it and tries again instead of
    /// announcing a message that is not there.
    func recordChat(_ message: ReadMessage, from keySet: KeySet) -> RecordResult? {
        guard let group = groups.first(where: { $0.id == keySet.groupID }) else { return nil }
        guard let result = try? book.record(message, group: group, room: keySet.room, chat: true) else { return nil }
        chatVersion += 1
        return result
    }

    /// True when the store already holds a message with this identity (same 5-minute slot, salt, flags and text).
    func holds(_ message: ReadMessage, from keySet: KeySet) -> Bool {
        let id = StoredMessage.identity(of: message, groupID: keySet.groupID, room: keySet.room)
        return ((try? book.messages(groupID: keySet.groupID)) ?? []).contains { $0.id == id }
    }

    /// Deleted, purged or already read once: a relay's copy is not shown again.
    func isForgotten(_ message: ReadMessage, from keySet: KeySet) -> Bool {
        (try? book.isForgotten(id: StoredMessage.identity(of: message, groupID: keySet.groupID, room: keySet.room))) ?? false
    }

    func forget(_ message: ReadMessage, from keySet: KeySet) {
        try? book.forget(id: StoredMessage.identity(of: message, groupID: keySet.groupID, room: keySet.room))
    }

    /// Received chat messages only (export); sent ones live in the chat, and Receive keeps no words.
    func messages() -> [StoredMessage] { ((try? book.messages()) ?? []).filter { !$0.isOutgoing && !$0.isOpenedInReceive } }

    func activeGroupMessages() -> [StoredMessage] { messages().filter { $0.groupID == activeGroup?.id } }

    /// Sent and received by chat for one group, oldest first. Messages decrypted in Receive are left out:
    /// their words never show in Chat.
    func chatMessages(groupID: UUID) -> [StoredMessage] {
        ((try? book.messages(groupID: groupID)) ?? []).filter { !$0.isOpenedInReceive }.sorted { $0.recordedAt < $1.recordedAt }
    }

    func recordSent(_ message: ReadMessage, from keySet: KeySet, via: String, relays: Int?) {
        guard let group = groups.first(where: { $0.id == keySet.groupID }) else { return }
        try? book.recordSent(message, group: group, room: keySet.room, via: via, relays: relays)
        chatVersion += 1
    }

    // MARK: Read receipts

    func setReceipts(_ on: Bool, for group: ChatGroup) {
        try? book.setReceipts(on, for: group.id)
        reload()
        chatVersion += 1
    }

    /// What to send for a group: this phone's reader tag, the group's receipt keys, and the messages not
    /// yet reported (now marked as reported). Nil when receipts are off or nothing is new.
    func takeReceipt(for group: ChatGroup) -> (reader: UInt16, keys: Keys, refs: [UInt64])? {
        guard receiptGroups.contains(group.id), let setting = (try? book.receiptSetting(for: group.id)) ?? nil,
              let keys = (try? book.keys(for: group)) ?? nil,
              let refs = try? book.takeUnreported(groupID: group.id), !refs.isEmpty else { return nil }
        return (setting.reader, keys.receiptKeys, refs)
    }

    /// Every group's receipt keys, in group order, for opening a receipt.
    func receiptKeySets() -> [(groupID: UUID, keys: Keys)] {
        keySets().filter { $0.room.isEmpty }.map { ($0.groupID, $0.keys.receiptKeys) }
    }

    func applyReceipt(_ receipt: ReadReceipt.Opened, groupID: UUID) {
        if (try? book.applyReceipt(groupID: groupID, reader: receipt.reader, refs: receipt.refs)) == true { chatVersion += 1 }
    }

    /// Drops what has outlived the retention period. Called at launch, on returning to the app, and on each record.
    func purgeExpired() { _ = try? book.purgeExpired() }

    func save(name: String, prepared: PreparedGroup) throws {
        try book.add(name: name, prepared: prepared)
        reload()
    }
}

#if DEBUG
extension GroupModel {
    /// `-seed-demo` for simulator screenshots: a separate vault with one throwaway group and a draft.
    /// Only seeds when that vault is empty. Add `-reset-demo` for a clean start.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupModel {
        guard arguments.contains("-seed-demo") else {
            let vault = Vault()
            vault.dropSecretsLeftFromEarlierInstall()
            return GroupModel(vault: vault)
        }
        let dir = URL.temporaryDirectory.appending(path: "dlchat-demo-vault", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.demo", directory: dir)
        // `-reset-demo` starts clean. The demo Keychain items survive between simulator runs, so a PIN left
        // behind by an earlier or failed run would otherwise open the next launch on the lock screen.
        if arguments.contains("-reset-demo") { try? vault.wipe() }
        return GroupModel(vault: vault)
    }

    func seedDemoIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) async {
        // `-no-demo-group`: the throwaway vault starts with no group, as a first run does (welcome UI test).
        guard arguments.contains("-seed-demo"), !arguments.contains("-no-demo-group"), groups.isEmpty else { return }
        guard let prepared = try? await prepareNew(words: 10) else { return }
        // `-store-shots`: the App Store screenshots' group, draft and conversation (`scripts/store-screenshots.sh`).
        guard arguments.contains("-store-shots") else {
            try? save(name: "Demo group", prepared: prepared)
            try? setDraft("need water at north gate", for: activeGroup?.id)
            return
        }
        try? save(name: "Maple Street", prepared: prepared)
        try? setDraft("Water truck is at the school until 4", for: activeGroup?.id)
        try? book.seedStoreChat()
        reload()
    }

    /// `-seed-history N`: fills the demo group's history (see `GroupBook.seedHistory`).
    func seedHistoryIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-seed-demo"), let i = arguments.firstIndex(of: "-seed-history"),
              arguments.indices.contains(i + 1), let count = Int(arguments[i + 1]) else { return }
        try? book.seedHistory(count)
        reload()
    }
}
#else
extension GroupModel {
    static func make() -> GroupModel {
        let vault = Vault()
        vault.dropSecretsLeftFromEarlierInstall()
        return GroupModel(vault: vault)
    }
}
#endif
