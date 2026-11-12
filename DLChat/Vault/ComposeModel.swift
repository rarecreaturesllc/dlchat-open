import DLCore
import Foundation
import Observation

/// The message being written. The text is kept per group in memory only, so switching groups keeps
/// it but a crash, kill or relaunch does not bring it back. The spoken words are made only when the
/// person asks to read them.
@MainActor
@Observable
final class ComposeModel {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            // Voice typing writing the message it just sent back into the box: keep the box empty.
            if echo.isEcho(text) {
                text = ""
                count = 0
                scheduleSave()
                return
            }
            count = Composer.wordCount(text: text)
            scheduleSave()
        }
    }
    /// Room word the next message is sealed under; empty is the group's default room.
    var room = ""
    /// Hidden option: seal the next message with the duress flag so the receiver is warned.
    /// Shows no mark in the words, and is cleared when the read-out closes.
    var duress = false
    /// Ask receivers to show the message and not keep it (flag bit 1).
    var readOnce = false
    var flags: UInt8 { (duress ? 1 : 0) | (readOnce ? 2 : 0) }
    private(set) var count = 0
    private(set) var words: [String] = []
    /// The text inside the message QR code, made when the person asks to show it.
    private(set) var qr = ""
    /// The audio samples for the tone modem, made when the person asks to play the message as sound.
    private(set) var tone: [Float] = []
    private(set) var problem: String?

    @ObservationIgnored private let groups: GroupModel
    @ObservationIgnored private var loadedFor: UUID?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var echo = SentEcho()

    init(groups: GroupModel) {
        self.groups = groups
    }

    var group: ChatGroup? { groups.activeGroup }

    /// Call at launch and whenever the first group changes. Text typed before any group existed
    /// moves to the new group rather than being replaced by its empty draft.
    func syncGroup() {
        let id = group?.id
        guard !loaded || id != loadedFor else { return }
        let carried = loaded && loadedFor == nil ? text : ""
        if loaded, loadedFor != nil { flush() }
        if !carried.isEmpty { try? groups.setDraft("", for: nil) }
        loaded = true
        loadedFor = id
        room = ""
        let saved = groups.draft(for: id)
        text = saved.isEmpty ? carried : saved
        if saved.isEmpty, !carried.isEmpty { flush() }
    }

    /// Keeps the draft (in memory) now. Used on backgrounding, where a delayed save might not run.
    func flush() {
        saveTask?.cancel()
        guard loaded else { return }
        // A removed group's draft was erased with it; do not write it back.
        if let loadedFor, !groups.groups.contains(where: { $0.id == loadedFor }) { return }
        do {
            try groups.setDraft(text, for: loadedFor)
            problem = nil
        } catch {
            problem = "The draft could not be saved."
        }
    }

    /// Seals the text with the group's keys. Returns false and sets `problem` on failure.
    @discardableResult
    func prepareWords() -> Bool {
        guard let made = sealActive({ try Composer.compose(text: text, keys: $0, flags: flags) }) else { return false }
        words = made
        return true
    }

    /// Seals the text as a QR code payload with the group's keys. Returns false and sets `problem` on failure.
    @discardableResult
    func prepareQR() -> Bool {
        guard let made = sealActive({ try Composer.composeQR(text: text, keys: $0, flags: flags) }) else { return false }
        qr = made
        return true
    }

    /// Seals the text as tone modem audio with the group's keys. Returns false and sets `problem` on failure.
    @discardableResult
    func prepareTone() -> Bool {
        guard let made = sealActive({ try Composer.composeTone(text: text, keys: $0, flags: flags) }) else { return false }
        tone = made
        return true
    }

    /// Seals for the active group and the room picked on Send.
    private func sealActive<T>(_ make: (Keys) throws -> T) -> T? {
        guard let group else { flush(); problem = "Create or join a group first."; return nil }
        return seal(for: group, room: room, make)
    }

    /// Send > Encrypt Words for a chosen chat: the text sealed as words for `target` and its `room`.
    /// Nil, with `problem` set, on failure.
    func sealedWords(for target: ChatGroup, room: String) -> [String]? {
        seal(for: target, room: room) { try Composer.compose(text: text, keys: $0, flags: flags) }
    }

    /// Send > Encrypt Sound for a chosen chat: the tone frame for `target` and its `room`, as `ChatCarry` text.
    func sealedSound(for target: ChatGroup, room: String) -> String? {
        seal(for: target, room: room) { try ChatCarry.text(.sound, frame: Composer.composeToneFrame(text: text, keys: $0, flags: flags)) }
            .flatMap { $0 }
    }

    private func seal<T>(for target: ChatGroup, room: String, _ make: (Keys) throws -> T) -> T? {
        flush()
        do {
            guard let keys = try groups.keys(for: target, room: target.rooms.contains(room) ? room : "") else {
                problem = "This group's key is missing. Join it again with its phrase."
                return nil
            }
            let made = try make(keys)
            problem = nil
            return made
        } catch ComposerError.tooLongForSound {
            problem = "Too long for sound. Shorten the message to send it as sound."
            return nil
        } catch {
            problem = "Type a message with letters or numbers first."
            return nil
        }
    }

    /// After a post in Chat: the draft is sent, so the box empties like Chat's own Send.
    func sent() {
        echo.sent(text)
        text = ""
        readOnce = false
        duress = false
    }

    /// Seals the text as a Nearby wire message with the group's keys. Nil, with `problem` set, on failure.
    func prepareNearby() -> Data? {
        sealActive { try Composer.composeNearby(text: text, keys: $0, flags: flags, callSign: groups.callSign) }
            .map { NearbyWire.wire(frame: $0, ttl: NearbyWire.startTTL) }
    }

    /// After a wipe: forget the text, the words and any pending save, and write nothing, so no draft
    /// reaches a fresh store.
    func discard() {
        loaded = false
        loadedFor = nil
        text = ""
        saveTask?.cancel()
        words = []
        qr = ""
        tone = []
        room = ""
        duress = false
        readOnce = false  // after a wipe or duress PIN the app must look untouched
        problem = nil
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
