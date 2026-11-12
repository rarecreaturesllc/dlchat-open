import Foundation

/// A message read from heard words: the English text, when it was sent, and what to warn about.
public struct ReadMessage: Equatable {
    public let text: String
    public let sentAt: Date
    public let flags: UInt8
    /// The sender's 6-bit random salt; part of the identity used to spot a repeated message.
    public let salt: UInt8
    /// Position in the `trying` list of the keys that opened it.
    public let keysIndex: Int
    /// Set when one word had to be changed or filled in. The screen must say so and name the word.
    public let repair: Repaired?
    /// The sender's call sign, when their Chat message carried one (see `CallSign`).
    public var callSign: CallSign? = nil
    /// The earlier Chat message this one answers, when the sender swiped to reply (see `ReplyTo`).
    public var replyTo: ReplyTo? = nil

    /// Bit 0 of the flags: the sender marked the message as sent under pressure (blueprint section 7).
    public var duress: Bool { flags & 1 != 0 }
    /// Bit 1 of the flags: the sender asked that the message be shown and not kept.
    public var readOnce: Bool { flags & 2 != 0 }
}

/// How a send time compares with this phone's clock.
public enum TimeNote: Equatable {
    case normal
    /// Sent time is ahead of this phone's clock: one of the clocks is wrong.
    case clockMayDiffer
    /// Sent more than a day ago: a replay is possible.
    case old
}

/// Turns the words a listener typed into a message. Word entry, suggestions and the
/// give-up states live here so they can be tested without the UI.
public enum Receiver {
    /// Fewest words a voice message can have (tag, header, four body words).
    public static var minimumWords: Int {
        (Composer.voiceTagBits + WordCodec.minimumBodyWords * WordList.bitsPerWord + Frame.headerBits) / WordList.bitsPerWord
    }

    /// Words that start with what has been typed, in list order.
    public static func suggestions(prefix: String, limit: Int = 6) -> [String] {
        let p = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.isEmpty, p != Repair.missingMarker else { return [] }
        return Array(WordList.words.lazy.filter { $0.hasPrefix(p) }.prefix(limit))
    }

    /// Words that are `?` or not on the list. Repair can fill at most one.
    public static func gapCount(in words: [String]) -> Int {
        words.filter { $0 == Repair.missingMarker || WordList.index(of: $0) == nil }.count
    }

    /// Opens the words exactly as heard. Nil unless every word is on the list and the tag
    /// authenticates with one of the key sets.
    public static func read(
        words: [String], trying keys: [Keys], tagBits: Int = Composer.voiceTagBits
    ) -> ReadMessage? {
        guard words.count >= minimumWords, gapCount(in: words) == 0,
              let frame = try? WordCodec.decode(words),
              let opened = Frame.open(frame, tagBits: tagBits, trying: keys)
        else { return nil }
        return message(from: opened, repair: nil)
    }

    /// Single-word repair (a `?` or off-list word, or any one wrong word). The result carries
    /// the changed word so the screen can label it.
    public static func repair(
        words: [String], trying keys: [Keys], tagBits: Int = Composer.voiceTagBits
    ) -> ReadMessage? {
        guard words.count >= minimumWords,
              let found = Repair.search(words: words, tagBits: tagBits, trying: keys)
        else { return nil }
        return message(from: found.opened, repair: found)
    }

    /// Opens the text of a scanned QR code. Nil if it is not a frame or no key set authenticates it.
    public static func readQR(payload: String, trying keys: [Keys]) -> ReadMessage? {
        guard let frame = QRTransport.frame(from: payload),
              let opened = Frame.open(frame, tagBits: QRTransport.tagBits, trying: keys)
        else { return nil }
        return message(from: opened, repair: nil)
    }

    /// Opens the bytes of a decoded tone burst. Nil if they are not a frame or no key set authenticates them.
    public static func readTone(payload: Data, trying keys: [Keys]) -> ReadMessage? {
        guard let frame = Modem.frame(from: payload),
              let opened = Frame.open(frame, tagBits: QRTransport.tagBits, trying: keys)
        else { return nil }
        return message(from: opened, repair: nil)
    }

    public static func timeNote(sentAt: Date, now: Date = Date()) -> TimeNote {
        let ahead = sentAt.timeIntervalSince(now)
        if ahead > Frame.slotSeconds { return .clockMayDiffer }
        return ahead < -24 * 3600 ? .old : .normal
    }

    private static func message(from opened: Opened, repair: Repaired?) -> ReadMessage? {
        var end = 0
        guard var text = try? TextCodec.decode(opened.body, end: &end) else { return nil }
        // Encrypted words or sound posted in Chat: shown as their marker and words (see `ChatCarry`).
        // Trailers after END, in order: punctuation (plain text only), a reply reference, the call sign.
        // Older senders send none; each is found by its own marker, so a missing one is skipped.
        var after = end
        if let carried = ChatCarry.read(marker: text, body: opened.body, from: end) {
            text = carried
            after = end + 8 + Int(opened.body.value(at: end, width: 8)) * WordList.bitsPerWord
        } else {
            // Chat text's ! ? . , ride after END (see `Punctuation`).
            let words = text.split(separator: " ").map(String.init)
            let marks = Punctuation.read(opened.body, from: end, wordCount: words.count)
            if !marks.isEmpty {
                text = Punctuation.apply(marks, to: words)
                after = end + Punctuation.trailerBits(count: marks.count)
            }
        }
        let replyTo = ReplyTo.read(opened.body, from: after)
        if replyTo != nil { after += ReplyTo.bitCount }
        return ReadMessage(
            text: text, sentAt: opened.sentAt, flags: opened.flags, salt: opened.salt,
            keysIndex: opened.keysIndex, repair: repair, callSign: CallSign.read(opened.body, from: after), replyTo: replyTo)
    }
}
