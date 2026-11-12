import DLCore
import Foundation
import Observation

/// A practice run of send and receive with no radio and no real group. Each run makes a throwaway
/// phrase in memory, seals a fixed sample message with it, and lets the person read the words out
/// and then type them back as a listener would. Nothing is saved, and the real groups are untouched.
@MainActor
@Observable
final class PracticeModel {
    enum Step: Equatable { case intro, say, listen, done }

    nonisolated static let message = "meet at the bridge at noon"

    private(set) var step: Step = .intro
    private(set) var words: [String] = []
    private(set) var entered: [String] = []
    private(set) var decoded: String?
    private(set) var repairNote: String?
    private(set) var preparing = false
    private(set) var problem: String?
    var typed = ""

    @ObservationIgnored private var keys: Keys?
    @ObservationIgnored private var generation = 0

    var gaps: Int { Receiver.gapCount(in: entered) }
    var suggestions: [String] { Receiver.suggestions(prefix: typed) }

    /// Makes the throwaway phrase and message. Key derivation is slow, so it runs off the main actor.
    func begin() async {
        guard !preparing else { return }
        preparing = true
        problem = nil
        let made = await Task.detached { () -> (Keys, [String])? in
            guard let phrase = try? Phrase.generate(words: 10) else { return nil }
            let keys = Keys(phrase: phrase)
            guard let words = try? Composer.compose(text: PracticeModel.message, keys: keys) else { return nil }
            return (keys, words)
        }.value
        preparing = false
        guard let made else { problem = "The practice message could not be made. Try again."; return }
        keys = made.0
        words = made.1
        reset()
        step = .say
    }

    func startListening() { step = .listen }

    func backToWords() { step = .say }

    func restart() async {
        step = .intro
        reset()
        await begin()
    }

    /// Adds what is typed if it is a listed word, `?`, or the only suggestion. Returns false when it was left in the field.
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

    /// Pasted or dictated text with several words: every finished word is added, the rest stays typed.
    func ingestTyped() {
        guard typed.contains(where: { $0.isWhitespace || $0 == "," }) else { return }
        let parts = typed.split(omittingEmptySubsequences: false, whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
        guard parts.count > 1 else { typed = ""; return }
        for part in parts.dropLast() where !part.isEmpty { entered.append(part.lowercased()) }
        typed = parts.last ?? ""
        recompute()
    }

    private func reset() {
        generation += 1
        entered = []
        typed = ""
        decoded = nil
        repairNote = nil
    }

    private func recompute() {
        generation += 1
        decoded = nil
        repairNote = nil
        guard let keys, entered.count >= Receiver.minimumWords else { return }
        if gaps == 0 {
            if let message = Receiver.read(words: entered, trying: [keys]) { finish(message) }
        } else if gaps == 1 {
            let words = entered
            let mine = generation
            Task {
                let found = await Task.detached { Receiver.repair(words: words, trying: [keys]) }.value
                guard mine == generation, let found else { return }
                finish(found)
            }
        }
    }

    private func finish(_ message: ReadMessage) {
        decoded = message.text
        if let repair = message.repair {
            repairNote = repair.wasMissing
                ? "You marked word \(repair.position + 1) with ?, and DLChat filled it in."
                : "Word \(repair.position + 1) was wrong, and DLChat fixed it."
        }
        step = .done
    }
}
