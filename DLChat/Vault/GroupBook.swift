import DLCore
import Foundation

/// Group metadata kept in the sealed store. Phrases and master keys live in the Keychain.
struct ChatGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var wordCount: Int
    var createdAt: Date
    var lastUsedAt: Date
    var sortIndex: Int
    var rooms: [String]
}

/// What went wrong when a typed phrase was rejected, in words the person can act on.
enum JoinProblem: Error, Equatable {
    case wrongLength(Int)
    case unknownWord(position: Int, word: String)
    case badChecksum
    case alreadyJoined(name: String)

    var message: String {
        switch self {
        case .wrongLength(let n):
            return "A phrase has 10, 15 or 20 words. You entered \(n)."
        case .unknownWord(let position, let word):
            return "Word \(position) (\"\(word)\") is not on the word list. Check how it is spelled."
        case .badChecksum:
            return "The words are all valid but the checksum fails: a word is wrong or out of order. Check each word against the original."
        case .alreadyJoined(let name):
            return "This phrase is already saved as \"\(name)\"."
        }
    }
}

/// A phrase with its slow-to-derive keys, ready to show and then save.
struct PreparedGroup {
    let phrase: Phrase
    let masterData: Data
    let safetyWords: [String]

    /// Runs PBKDF2 (600,000 rounds). Call off the main actor.
    init(phrase: Phrase) {
        let keys = Keys(phrase: phrase)
        self.phrase = phrase
        masterData = keys.masterData
        safetyWords = keys.safetyWords
    }
}

/// Read receipts turned on for one group on this phone (docs/design/read-receipts.md).
struct ReceiptSetting: Codable, Equatable {
    /// Random, so the group can count readers without learning who; new each time they are turned on.
    var reader: UInt16
    /// Messages received before this are never reported.
    var since: Date
}

/// Create, join and list groups on top of the Vault.
final class GroupBook {
    private let vault: Vault

    init(vault: Vault) {
        self.vault = vault
    }

    // MARK: Phrase entry

    static func parse(_ text: String) -> Result<Phrase, JoinProblem> {
        do {
            return .success(try Phrase.parse(text))
        } catch PhraseError.unsupportedLength(let n) {
            return .failure(.wrongLength(n))
        } catch PhraseError.unknownWord(let i) {
            let words = text.split(whereSeparator: \.isWhitespace)
            return .failure(.unknownWord(position: i + 1, word: words.indices.contains(i) ? String(words[i]) : ""))
        } catch {
            return .failure(.badChecksum)
        }
    }

    // MARK: Groups

    func groups() throws -> [ChatGroup] {
        try loadStore().groups.sorted { $0.sortIndex < $1.sortIndex }
    }

    func activeGroupID() throws -> UUID? { try loadStore().activeGroupID }

    /// Chooses the group Send, History and rooms follow. Unknown ids are ignored.
    func setActive(_ id: UUID) throws {
        var file = try loadForChange()
        guard file.groups.contains(where: { $0.id == id }), file.activeGroupID != id else { return }
        file.activeGroupID = id
        try saveStore(file)
    }

    /// Moves groups the way `Array.move(fromOffsets:toOffset:)` does, then renumbers `sortIndex`.
    func moveGroups(from source: IndexSet, to destination: Int) throws {
        var file = try loadForChange()
        var all = file.groups.sorted { $0.sortIndex < $1.sortIndex }
        all.move(fromOffsets: source, toOffset: destination)
        for i in all.indices { all[i].sortIndex = i }
        file.groups = all
        try saveStore(file)
    }

    /// Deletes the group's phrase and key from the Keychain, then its messages, draft and place in the list.
    /// Keychain items go first: if that fails nothing else is touched and the group stays whole.
    func removeGroup(_ group: ChatGroup) throws {
        var file = try loadForChange()
        guard file.groups.contains(where: { $0.id == group.id }) else { return }
        try vault.removeSecret(account: Self.phraseAccount(group.id))
        try vault.removeSecret(account: Self.masterAccount(group.id))
        file.groups.removeAll { $0.id == group.id }
        file.messages.removeAll { $0.groupID == group.id }
        file.drafts[Self.draftKey(group.id)] = nil
        file.receipts[group.id.uuidString] = nil
        if file.activeGroupID == group.id { file.activeGroupID = nil }
        let ordered = file.groups.sorted { $0.sortIndex < $1.sortIndex }
        for (i, g) in ordered.enumerated() { if let j = file.groups.firstIndex(where: { $0.id == g.id }) { file.groups[j].sortIndex = i } }
        try saveStore(file)
    }

    /// Adds a room word to a group. Lowercased, so "North" and "north" are one room.
    @discardableResult
    func addRoom(_ name: String, to group: ChatGroup) throws -> ChatGroup {
        let room = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var file = try loadForChange()
        guard !room.isEmpty, let i = file.groups.firstIndex(where: { $0.id == group.id }) else { return group }
        if !file.groups[i].rooms.contains(room) {
            file.groups[i].rooms.append(room)
            try saveStore(file)
        }
        return file.groups[i]
    }

    // MARK: Received messages

    func retention() throws -> Retention { try loadStore().retention }

    func setRetention(_ value: Retention, now: Date = Date()) throws {
        var file = try loadForChange()
        file.retention = value
        file.purge(now: now)
        try saveStore(file)
    }

    /// Keeps a received message, or says it was heard before. With retention off nothing is kept
    /// and a repeat cannot be told. `opened`: decrypted in Receive. Only its fingerprint is kept (to spot a repeat),
    /// never its words, and it is never shown in Chat.
    /// `chat`: it came in by a chat carrier (relays, radio), so read receipts may report it. Never for a
    /// message decrypted on Receive: that is acknowledged only by hand ("Decrypted").
    @discardableResult
    func record(_ message: ReadMessage, group: ChatGroup, room: String, opened: Bool = false, chat: Bool = false, now: Date = Date()) throws -> RecordResult {
        var file = try loadForChange()
        let before = file.messages.count
        file.purge(now: now)
        var changed = file.messages.count != before
        let id = StoredMessage.identity(of: message, groupID: group.id, room: room)
        defer { if changed, file.retention != .off { try? saveStore(file) } }
        if let i = file.messages.firstIndex(where: { $0.id == id }) {
            // Relays hand every recent message over again at each launch. That is not the person hearing it
            // again, so it is not counted, and the whole store is not rewritten for it.
            if !chat { file.messages[i].timesHeard += 1; changed = true }
            // The same message also came by chat itself (relays or radio): it belongs in Chat after all.
            if !opened, file.messages[i].isOpenedInReceive {
                file.messages[i].opened = nil
                file.messages[i].text = message.text
                changed = true
            }
            if chat, !opened, file.messages[i].receiptRef == nil {
                file.messages[i].receiptRef = ReadReceipt.ref(of: message, room: room)
                changed = true
            }
            return .repeated(firstHeard: file.messages[i].recordedAt)
        }
        guard file.retention != .off else { return .new }
        changed = true
        file.messages.append(StoredMessage(
            id: id, groupID: group.id, room: room.lowercased(), text: opened ? "" : message.text, sentAt: message.sentAt,
            recordedAt: now, repairedWord: message.repair?.replacement, duress: message.duress, timesHeard: 1,
            opened: opened ? true : nil, callSign: message.callSign, replyTo: message.replyTo?.fingerprint,
            receiptRef: chat && !opened ? ReadReceipt.ref(of: message, room: room) : nil))
        return .new
    }

    /// Whether Receive > Acknowledged already posted "Decrypted" for the message with this identity.
    func isAcknowledged(id: String) throws -> Bool {
        try loadStore().messages.contains { $0.id == id && $0.acknowledged == true }
    }

    /// Notes on the message's fingerprint that "Decrypted" was posted for it. Nothing to note when no
    /// fingerprint is kept (read once, or nothing is kept): the caller remembers that until the app closes.
    func markAcknowledged(id: String) throws {
        var file = try loadForChange()
        guard let i = file.messages.firstIndex(where: { $0.id == id }), file.messages[i].acknowledged != true else { return }
        file.messages[i].acknowledged = true
        try saveStore(file)
    }

    /// Keeps a message this phone sent, for the chat. Its id is the same identity a received copy
    /// would get, so our own message echoed back by a relay is recognised, not shown twice.
    func recordSent(_ message: ReadMessage, group: ChatGroup, room: String, via: String, relays: Int?, now: Date = Date()) throws {
        var file = try loadForChange()
        file.purge(now: now)
        // With retention off a sent message is not kept, except one still waiting to go out: dropping it would lose it.
        guard file.retention != .off || via == "queued" else { return }
        let id = StoredMessage.identity(of: message, groupID: group.id, room: room)
        if let i = file.messages.firstIndex(where: { $0.id == id }) {
            file.messages[i].outgoing = true
            file.messages[i].via = via
            file.messages[i].relays = relays
            file.messages[i].receiptRef = ReadReceipt.ref(of: message, room: room)
        } else {
            file.messages.append(StoredMessage(
                id: id, groupID: group.id, room: room.lowercased(), text: message.text, sentAt: message.sentAt,
                recordedAt: now, repairedWord: nil, duress: message.duress, timesHeard: 1,
                outgoing: true, via: via, relays: relays, replyTo: message.replyTo?.fingerprint,
                receiptRef: ReadReceipt.ref(of: message, room: room)))
        }
        try saveStore(file)
    }

    /// Newest first. A nil room means every room of the group.
    func messages(groupID: UUID? = nil, room: String? = nil) throws -> [StoredMessage] {
        try loadStore().messages
            .filter { (groupID == nil || $0.groupID == groupID) && (room == nil || $0.room == room?.lowercased()) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func deleteMessage(id: String, now: Date = Date()) throws {
        var file = try loadForChange()
        let before = file.messages.count
        file.messages.removeAll { $0.id == id }
        guard file.messages.count != before else { return }
        file.forgotten[id] = now.addingTimeInterval(StoreFile.forgetFor)
        try saveStore(file)
    }

    /// A message deleted, purged or read once: relays still hold a sealed copy for up to
    /// `Online.lifetime`, and it must not come back as new after a relaunch.
    func isForgotten(id: String, now: Date = Date()) throws -> Bool {
        guard let until = try loadStore().forgotten[id] else { return false }
        return until > now
    }

    func forget(id: String, now: Date = Date()) throws {
        var file = try loadForChange()
        file.forgotten[id] = now.addingTimeInterval(StoreFile.forgetFor)
        try saveStore(file)
    }

    /// Removes messages older than the retention period. Returns how many went.
    @discardableResult
    func purgeExpired(now: Date = Date()) throws -> Int {
        // Most of the time nothing is due: answer from the cached copy (runs on every return to the app).
        var peek = try loadStore()
        let due = peek.messages.count
        peek.purge(now: now)
        guard peek.messages.count != due else { return 0 }
        var file = try loadForChange()
        let before = file.messages.count
        file.purge(now: now)
        if file.messages.count != before { try saveStore(file) }
        return before - file.messages.count
    }

    // MARK: Read receipts

    /// Groups this phone has read receipts on for. Off unless turned on, per group.
    func receiptGroups() throws -> Set<UUID> { Set(try loadStore().receipts.keys.compactMap(UUID.init(uuidString:))) }

    func receiptSetting(for groupID: UUID) throws -> ReceiptSetting? { try loadStore().receipts[groupID.uuidString] }

    /// On: a new random reader tag, and only messages received from now on are reported. Off: forgets the tag.
    func setReceipts(_ on: Bool, for groupID: UUID, now: Date = Date()) throws {
        var file = try loadForChange()
        guard file.groups.contains(where: { $0.id == groupID }), (file.receipts[groupID.uuidString] != nil) != on else { return }
        file.receipts[groupID.uuidString] = on ? ReceiptSetting(reader: UInt16.random(in: 0...UInt16.max), since: now) : nil
        try saveStore(file)
    }

    /// References of received messages in the group not yet reported read, oldest first, now marked as
    /// reported. Empty when receipts are off. Encrypted words and sounds are left out: "Decrypted" covers those.
    func takeUnreported(groupID: UUID) throws -> [UInt64] {
        var file = try loadForChange()
        guard let setting = file.receipts[groupID.uuidString] else { return [] }
        var refs: [(Date, UInt64)] = []
        for i in file.messages.indices {
            let m = file.messages[i]
            guard m.groupID == groupID, !m.isOutgoing, m.receiptSent != true, let ref = m.receiptRef,
                  m.recordedAt >= setting.since, ChatCarry.parse(m.text) == nil else { continue }
            file.messages[i].receiptSent = true
            refs.append((m.recordedAt, ref))
        }
        guard !refs.isEmpty else { return [] }
        try saveStore(file)
        return refs.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Notes that `reader` read these of our sent messages. Ignored unless this phone has receipts on for
    /// the group (they go both ways or not at all), and for our own tag. True when anything changed.
    @discardableResult
    func applyReceipt(groupID: UUID, reader: UInt16, refs: [UInt64]) throws -> Bool {
        var file = try loadForChange()
        guard let setting = file.receipts[groupID.uuidString], reader != setting.reader else { return false }
        let wanted = Set(refs)
        var changed = false
        for i in file.messages.indices where file.messages[i].groupID == groupID && file.messages[i].isOutgoing {
            guard let ref = file.messages[i].receiptRef, wanted.contains(ref) else { continue }
            var readers = file.messages[i].readBy ?? []
            guard !readers.contains(reader) else { continue }
            readers.append(reader)
            file.messages[i].readBy = readers
            changed = true
        }
        if changed { try saveStore(file) }
        return changed
    }

    // MARK: Drafts

    /// Erases every draft in the store. The app keeps drafts in memory only (`GroupModel`); builds up
    /// to 15 saved them here, so each launch clears what those left. Writes nothing when there are none.
    func dropDrafts() throws {
        guard try !loadStore().drafts.isEmpty else { return }
        var file = try loadForChange()
        guard !file.drafts.isEmpty else { return }
        file.drafts = [:]
        try saveStore(file)
    }

    /// Unsent message text for a group (`nil` key: no group yet). Empty when none was saved.
    /// The app no longer calls these two; tests use them to plant a draft as builds up to 15 did.
    func draft(for groupID: UUID?) throws -> String {
        try loadStore().drafts[Self.draftKey(groupID)] ?? ""
    }

    func setDraft(_ text: String, for groupID: UUID?) throws {
        var file = try loadForChange()
        let key = Self.draftKey(groupID)
        guard (file.drafts[key] ?? "") != text else { return }
        if text.isEmpty { file.drafts[key] = nil } else { file.drafts[key] = text }
        try saveStore(file)
    }

    @discardableResult
    func add(name: String, prepared: PreparedGroup, now: Date = Date()) throws -> ChatGroup {
        var file = try loadForChange()
        var all = file.groups.sorted { $0.sortIndex < $1.sortIndex }
        for existing in all where try phraseText(for: existing) == prepared.phrase.text {
            throw JoinProblem.alreadyJoined(name: existing.name)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = ChatGroup(
            id: UUID(), name: trimmed.isEmpty ? "Group \(all.count + 1)" : trimmed,
            wordCount: prepared.phrase.indices.count, createdAt: now, lastUsedAt: now,
            sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1, rooms: [])
        try vault.setSecret(Data(prepared.phrase.text.utf8), account: Self.phraseAccount(group.id))
        try vault.setSecret(prepared.masterData, account: Self.masterAccount(group.id))
        all.append(group)
        file.groups = all
        try saveStore(file)
        return group
    }

    func phraseText(for group: ChatGroup) throws -> String? {
        try vault.secret(account: Self.phraseAccount(group.id)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Fast: uses the cached master key. An empty room word means the group's default room.
    func keys(for group: ChatGroup, room: String = "") throws -> Keys? {
        try vault.secret(account: Self.masterAccount(group.id)).map { Keys(masterData: $0, room: room) }
    }

    // MARK: Call sign

    /// This phone's call sign, kept in the sealed store so a wipe removes it with everything else.
    func callSign() throws -> CallSign? { try loadStore().callSign }

    func setCallSign(_ value: CallSign?) throws {
        var file = try loadForChange()
        file.callSign = value
        try saveStore(file)
    }

    // MARK: Storage

    private struct StoreFile: Codable {
        var groups: [ChatGroup] = []
        var drafts: [String: String] = [:]
        var messages: [StoredMessage] = []
        var retention = Retention.standard
        var activeGroupID: UUID?
        /// Identities (hashes, no text) of messages that must not be stored again, until the date.
        var forgotten: [String: Date] = [:]
        var callSign: CallSign?
        /// Read receipts, by group id: present only for groups this phone turned them on for.
        var receipts: [String: ReceiptSetting] = [:]

        /// Relays keep events `Online.lifetime`; subscriptions reach 3 days further back than the last look.
        static let forgetFor = Online.lifetime + 3 * 86_400

        init() {}

        mutating func purge(now: Date) {
            forgotten = forgotten.filter { $0.value > now }
            guard let keep = retention.seconds else { return }
            // With "Don't keep", a sent message still waiting for a connection stays until it has gone out
            // (or is deleted by hand): purging it would lose it without a word.
            let due: (StoredMessage) -> Bool = {
                now.timeIntervalSince($0.recordedAt) >= keep && !(keep == 0 && $0.outgoing == true && $0.via == "queued")
            }
            for m in messages where due(m) { forgotten[m.id] = now.addingTimeInterval(Self.forgetFor) }
            messages.removeAll(where: due)
        }

        // Stores written before drafts, messages or retention existed lack those keys.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            groups = try c.decode([ChatGroup].self, forKey: .groups)
            drafts = try c.decodeIfPresent([String: String].self, forKey: .drafts) ?? [:]
            messages = try c.decodeIfPresent([StoredMessage].self, forKey: .messages) ?? []
            retention = try c.decodeIfPresent(Retention.self, forKey: .retention) ?? .standard
            activeGroupID = try c.decodeIfPresent(UUID.self, forKey: .activeGroupID)
            forgotten = try c.decodeIfPresent([String: Date].self, forKey: .forgotten) ?? [:]
            callSign = try c.decodeIfPresent(CallSign.self, forKey: .callSign)
            receipts = try c.decodeIfPresent([String: ReceiptSetting].self, forKey: .receipts) ?? [:]
        }
    }

    /// The store as last read or written, while the file on disk is still that one. Each read otherwise
    /// decrypts and decodes the whole file, message history included, and launch alone reads it many times.
    /// It holds nothing the app does not already hold in memory, and is dropped as soon as a wipe starts.
    private var cached: (stamp: Vault.FileStamp, wipes: Int, file: StoreFile)?

    /// For reading only. Anything that changes the store and saves it uses `loadForChange()`.
    private func loadStore() throws -> StoreFile {
        try load(fresh: false)
    }

    /// Always reads the file itself before a change, as before the cache: if the store cannot be read (the
    /// iPhone is locked and the file is protected), the change fails instead of being made to a copy that cannot be saved.
    private func loadForChange() throws -> StoreFile {
        try load(fresh: true)
    }

    private func load(fresh: Bool) throws -> StoreFile {
        // Stamped before reading: a write in between leaves an old stamp behind, so the next load reads again.
        let stamp = vault.stamp()
        if !fresh, let cached, let stamp, cached.stamp == stamp, cached.wipes == vault.wipesStarted { return cached.file }
        cached = nil
        guard let data = try vault.readStore() else { return StoreFile() }
        LaunchTiming.mark("store.decode")
        let file = try Self.decoder.decode(StoreFile.self, from: data)
        if let stamp { cached = (stamp, vault.wipesStarted, file) }
        return file
    }

    /// The next load reads the file back once, so what is cached is exactly what was saved (dates keep whole seconds).
    private func saveStore(_ file: StoreFile) throws {
        cached = nil
        try vault.writeStore(try Self.encoder.encode(file))
    }

    /// Forgets the decrypted copy (the panic wipe calls this first).
    func dropCache() { cached = nil }

    #if DEBUG
    /// `-seed-history N` (demo vault only): N chat messages in the first group, to measure launch with a long history.
    func seedHistory(_ count: Int, now: Date = Date()) throws {
        var file = try loadForChange()
        guard let group = file.groups.first, file.messages.count < count else { return }
        for i in file.messages.count..<count {
            let at = now.addingTimeInterval(TimeInterval(i - count) * 60)
            file.messages.append(StoredMessage(
                id: "seed-\(i)", groupID: group.id, room: "", text: "Seeded message \(i): need water at the north gate by noon",
                sentAt: at, recordedAt: at, repairedWord: nil, duress: false, timesHeard: 1))
        }
        file.retention = .forever
        try saveStore(file)
    }

    /// `-store-shots` (demo vault only): a short neighbourhood conversation in the first group, for the
    /// App Store screenshots (`scripts/store-screenshots.sh`).
    func seedStoreChat(now: Date = Date()) throws {
        var file = try loadForChange()
        guard let group = file.groups.first, file.messages.isEmpty else { return }
        let lines: [(sign: CallSign?, text: String)] = [
            (CallSign("RUTH", color: 1), "Power is still out on our side. Does anyone have a spare lantern?"),
            (nil, "We have two. I'll bring one over after dinner."),
            (CallSign("DAN", color: 2), "The generator is running at number 14 if you need to charge a phone."),
            (CallSign("RUTH", color: 1), "Thanks. Is the bridge open yet?"),
            (nil, "Not yet. The county says tomorrow morning."),
        ]
        for (i, line) in lines.enumerated() {
            let at = now.addingTimeInterval(TimeInterval(i - lines.count) * 240)
            var message = StoredMessage(
                id: "store-\(i)", groupID: group.id, room: "", text: line.text,
                sentAt: at, recordedAt: at, repairedWord: nil, duress: false, timesHeard: 1)
            message.callSign = line.sign
            if line.sign == nil { message.outgoing = true; message.via = "online-tor"; message.relays = 3 }
            file.messages.append(message)
        }
        try saveStore(file)
    }
    #endif

    private static func draftKey(_ id: UUID?) -> String { id?.uuidString ?? "none" }

    private static func phraseAccount(_ id: UUID) -> String { "phrase/\(id.uuidString)" }
    private static func masterAccount(_ id: UUID) -> String { "master/\(id.uuidString)" }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
