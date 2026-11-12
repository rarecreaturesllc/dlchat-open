import Foundation

/// Keeps a sent message from coming back into the message box. Voice typing (the keyboard's
/// microphone) keeps its own copy of what it heard and writes it into the box again after Send has
/// emptied it, so the sent text "stays". A write of the same text just after sending is that echo.
struct SentEcho {
    private var text = ""
    private var at = Date.distantPast
    /// Long enough for dictation to finish and write back; far too short to type the message again.
    static let window: TimeInterval = 3

    mutating func sent(_ text: String, now: Date = .now) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        at = now
    }

    func isEcho(_ text: String, now: Date = .now) -> Bool {
        !self.text.isEmpty && now.timeIntervalSince(at) < Self.window
            && text.trimmingCharacters(in: .whitespacesAndNewlines) == self.text
    }
}
