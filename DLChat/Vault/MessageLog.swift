import CryptoKit
import DLCore
import Foundation

/// How long received messages (and the hashes that spot a repeat) are kept.
enum Retention: String, Codable, CaseIterable, Identifiable {
    case off, day, week, month, forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Don't keep"
        case .day: return "1 day"
        case .week: return "7 days"
        case .month: return "30 days"
        case .forever: return "Forever"
        }
    }

    /// Nil for `forever`; zero for `off`.
    var seconds: TimeInterval? {
        switch self {
        case .off: return 0
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .forever: return nil
        }
    }

    static let standard = Retention.week
}

/// One received message as kept in the sealed store. `id` is a SHA-256 over what makes a message
/// the same message, so hearing it again is recognised without keeping the words.
struct StoredMessage: Codable, Identifiable, Equatable {
    var id: String
    var groupID: UUID
    var room: String
    var text: String
    var sentAt: Date
    var recordedAt: Date
    var repairedWord: String?
    var duress: Bool
    var timesHeard: Int
    /// Chat: set on messages this phone sent (nil on everything stored before chat existed).
    var outgoing: Bool? = nil
    /// How a sent message left: "online", "nearby", "queued" (waiting for a connection).
    var via: String? = nil
    /// How many relays accepted it, when it went online.
    var relays: Int? = nil
    /// Opened in Receive (words, sound, QR, a sound file): only the fingerprint is kept, with empty text, so a
    /// repeat can be told. Never shown in Chat or exported.
    /// Chat shows only the "Decrypted" note the person sends with Acknowledged.
    var opened: Bool? = nil
    /// Acknowledged was used for this message, so "Decrypted" is not posted for it a second time.
    var acknowledged: Bool? = nil
    /// Received chat: the sender's call sign, when their message carried one.
    var callSign: CallSign? = nil
    /// Chat: the fingerprint of the earlier message this one answers (swipe to reply; see DLCore `ReplyTo`).
    var replyTo: UInt32? = nil
    /// Read receipts: the message's reference, the same on every phone (`ReadReceipt.ref`).
    var receiptRef: UInt64? = nil
    /// Received: this phone already said it read it. Sent: the readers' tags that said so.
    var receiptSent: Bool? = nil
    var readBy: [UInt16]? = nil

    var isOutgoing: Bool { outgoing == true }
    var isOpenedInReceive: Bool { opened == true }

    /// The reference a reply to this message carries. Every phone holding it computes the same one.
    var reference: ReplyTo { ReplyTo(sentAt: sentAt, text: text) }

    /// What History and exports show: encrypted words or sound posted in Chat are labelled, not shown raw.
    var shownText: String {
        switch ChatCarry.parse(text)?.kind {
        case .words?: return "Encrypted words: " + (ChatCarry.parse(text)?.words.joined(separator: " ") ?? "")
        case .sound?: return "Encrypted sound (open it from Chat)"
        case nil: return text
        }
    }

    static func identity(of message: ReadMessage, groupID: UUID, room: String) -> String {
        var data = Data(groupID.uuidString.utf8)
        data.append(0)
        data.append(Data(room.lowercased().utf8))
        data.append(0)
        data.append(Data(String(Int(message.sentAt.timeIntervalSince1970)).utf8))
        data.append(0)
        data.append(contentsOf: [message.salt, message.flags])
        data.append(Data(message.text.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum RecordResult: Equatable {
    case new
    /// Heard before; `firstHeard` is when it was first recorded.
    case repeated(firstHeard: Date)
}
