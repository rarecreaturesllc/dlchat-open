import DLCore
import Foundation
import Observation

/// The words heard so far and what they decode to. Kept by the root view, so switching to Send
/// and back keeps them. An exact read happens on every word; a single `?` is repaired
/// automatically (the listener marked it); a wrong word is repaired only when asked.
@MainActor
@Observable
final class DecodeModel {
    enum Outcome: Equatable {
        case typing
        case message(ReadMessage, groupName: String?)
        case repairing
        /// Asked to read or repair and nothing authenticated.
        case notRead(gaps: Int)
    }

    private(set) var entered: [String] = []
    private(set) var outcome: Outcome = .typing
    var typed = ""
    /// An encrypted sound tapped in Chat, waiting in Receive for Decrypt Sound (the tone frame's bytes).
    var pendingSound: Data?
    /// Receive > Decrypt Word by Word: the one-word field is open, for words read out on a call or a radio.
    var wordByWord = false
    /// Set when the message on screen was heard before; the time it was first recorded.
    private(set) var heardBefore: Date?
    /// Set when "Decrypted" was already posted for the message on screen: it can be decrypted again, not acknowledged again.
    private(set) var alreadyAcknowledged = false

    @ObservationIgnored private let groups: GroupModel
    @ObservationIgnored private var keySets: [KeySet] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastShown: (message: ReadMessage, result: RecordResult)?
    /// Messages acknowledged since the app opened, for those with no fingerprint kept (read once, or nothing kept).
    @ObservationIgnored private var acknowledged: Set<String> = []

    init(groups: GroupModel) {
        self.groups = groups
    }

    var gaps: Int { Receiver.gapCount(in: entered) }
    var suggestions: [String] { Receiver.suggestions(prefix: typed) }
    var hasEnoughWords: Bool { entered.count >= Receiver.minimumWords }
    var hasGroup: Bool { !groups.groups.isEmpty }

    var canRepair: Bool {
        guard hasEnoughWords, gaps <= 1 else { return false }
        if case .message = outcome { return false }
        return outcome != .repairing
    }

    /// Call when the groups change so the right keys are tried.
    func refreshKeys() {
        keySets = groups.keySets()
        recompute()
    }

    /// Adds what is typed if it is a listed word, `?`, or the only suggestion. Returns false when
    /// it was left in the field.
    @discardableResult
    func submit() -> Bool {
        let word = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if word == Repair.missingMarker || WordList.index(of: word) != nil {
            add(word)
            return true
        }
        let options = Receiver.suggestions(prefix: word, limit: 2)
        if options.count == 1 {
            add(options[0])
            return true
        }
        return false
    }

    func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespaces).lowercased()
        guard !w.isEmpty else { return }
        entered.append(w)
        typed = ""
        recompute()
    }

    func addMissing() { add(Repair.missingMarker) }

    func undo() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        recompute()
    }

    func clear() {
        pendingSound = nil
        wordByWord = false
        lastShown = nil
        entered = []
        typed = ""
        recompute()
    }

    /// Reads or repairs the words as they are. Sets `.notRead` when nothing authenticates.
    func repair() {
        guard canRepair else { return }
        run(automatic: false)
    }

    /// Opens the text of a scanned QR code with every group's keys. Returns false when nothing
    /// authenticates, leaving the screen as it was. Hearing the same message again, by QR or words, is a repeat.
    func readScanned(_ payload: String) -> Bool {
        guard !keySets.isEmpty,
              let message = Receiver.readQR(payload: payload, trying: keySets.map(\.keys)) else { return false }
        return showHeard(message)
    }

    /// Opens the bytes of a tone burst heard on the microphone, with the same rules as a scanned code.
    func readHeard(_ payload: Data) -> Bool {
        guard !keySets.isEmpty,
              let message = Receiver.readTone(payload: payload, trying: keySets.map(\.keys)) else { return false }
        return showHeard(message)
    }

    private func showHeard(_ message: ReadMessage) -> Bool {
        generation += 1
        lastShown = nil
        entered = []
        typed = ""
        show(message)
        return true
    }

    // MARK: Private

    /// Pasted or dictated text with several words: every finished word is added, the rest stays typed.
    /// Called by the view when the field changes.
    /// Words pasted from a chat: every word is entered, as if typed with spaces between them.
    func paste(_ text: String) {
        // Text copied straight off a Chat bubble on an older build still carries its marker.
        let words = ChatCarry.parse(text).map { $0.words.joined(separator: " ") } ?? text
        typed = words.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        ingestTyped()
    }

    func ingestTyped() {
        guard typed.contains(where: { $0.isWhitespace || $0 == "," }) else { return }
        let parts = typed.split(omittingEmptySubsequences: false, whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
        guard parts.count > 1 else { typed = ""; return }
        let rest = parts.last ?? ""
        for part in parts.dropLast() where !part.isEmpty { entered.append(part.lowercased()) }
        typed = rest
        recompute()
    }

    private func recompute() {
        generation += 1
        outcome = .typing
        heardBefore = nil
        alreadyAcknowledged = false
        guard hasEnoughWords, !keySets.isEmpty else { return }
        if gaps == 0 {
            if let message = Receiver.read(words: entered, trying: keySets.map(\.keys)) {
                show(message)
            }
        } else if gaps == 1 {
            run(automatic: true)
        }
    }

    private func run(automatic: Bool) {
        let words = entered
        let keys = keySets.map(\.keys)
        generation += 1
        let mine = generation
        if !automatic { outcome = .repairing }
        Task {
            let found = await Task.detached { Receiver.repair(words: words, trying: keys) }.value
            guard mine == generation else { return }
            if let found {
                show(found)
            } else if !automatic {
                outcome = .notRead(gaps: Receiver.gapCount(in: words))
            }
        }
    }

    /// Shows a read message and records it. Showing the same message again (undo, retype) is not a repeat.
    private func show(_ message: ReadMessage) {
        let result: RecordResult
        if message.readOnce {
            result = .new  // read once: shown, never recorded
        } else if let last = lastShown, last.message == message {
            result = last.result
        } else if keySets.indices.contains(message.keysIndex) {
            // Only a fingerprint is kept, to spot a repeat; the words are not saved, and Chat never shows them
            // (only the "Decrypted" note Acknowledged sends).
            result = groups.record(message, from: keySets[message.keysIndex], opened: true)
            lastShown = (message, result)
        } else {
            result = .new
        }
        if case .repeated(let first) = result { heardBefore = first } else { heardBefore = nil }
        alreadyAcknowledged = wasAcknowledged(message)
        outcome = .message(message, groupName: name(for: message))
    }

    private func identity(of message: ReadMessage) -> String? {
        guard keySets.indices.contains(message.keysIndex) else { return nil }
        return StoredMessage.identity(of: message, groupID: keySets[message.keysIndex].groupID, room: keySets[message.keysIndex].room)
    }

    private func wasAcknowledged(_ message: ReadMessage) -> Bool {
        guard let id = identity(of: message) else { return false }
        return acknowledged.contains(id) || groups.isAcknowledged(message, from: keySets[message.keysIndex])
    }

    /// Call once Acknowledged has posted "Decrypted" for `message`, so it is not posted for it again.
    func markAcknowledged(_ message: ReadMessage) {
        guard let id = identity(of: message) else { return }
        acknowledged.insert(id)
        groups.markAcknowledged(message, from: keySets[message.keysIndex])
        alreadyAcknowledged = true
    }

    /// Where Acknowledged posts "Decrypted" for `message`: the group and room it was sealed under.
    func replyTarget(for message: ReadMessage) -> (groupID: UUID, room: String)? {
        keySets.indices.contains(message.keysIndex) ? (keySets[message.keysIndex].groupID, keySets[message.keysIndex].room) : nil
    }

    /// What Acknowledged posts in Chat: this word only, never any of the decrypted message.
    nonisolated static let acknowledgedText = "Decrypted"

    /// The group name, only when there is more than one to tell apart.
    private func name(for message: ReadMessage) -> String? {
        guard groups.groups.count > 1, keySets.indices.contains(message.keysIndex) else { return nil }
        return keySets[message.keysIndex].groupName
    }
}
