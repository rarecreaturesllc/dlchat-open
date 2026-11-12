import CryptoKit
import Foundation

/// Which earlier Chat message a message answers (swipe a bubble to reply).
///
/// It names the message by a 32-bit fingerprint of what every phone that holds it already knows:
/// its 5-minute send slot and its text. Nothing of the original's words travels, and the reference
/// sits inside the sealed body, after the text (and after a carried frame), so relays and radios
/// never see it. Each phone looks the fingerprint up in its own chat; when the original is not
/// there (deleted, not kept, never heard) the reply says so.
///
/// On the wire: a 24-bit marker, then the fingerprint (32 bits), 7 bytes in all. Older versions
/// read it as padding and show the text alone. A message from an older version whose random
/// padding happens to start with the marker could show a stray "reply to a message not on this
/// phone": about 1 in 16 million of its shortest messages.
public struct ReplyTo: Codable, Equatable, Hashable {
    /// First 8 bits are zero, so plain text reading "dlwords" never mistakes it for a carried
    /// frame's word count (which must be at least `Receiver.minimumWords`).
    static let marker: UInt64 = 0x00D1E5
    static let markerBits = 24
    static let fingerprintBits = 32
    public static let bitCount = markerBits + fingerprintBits

    public let fingerprint: UInt32

    public init(fingerprint: UInt32) {
        self.fingerprint = fingerprint
    }

    /// The reference to a message sent at `sentAt` (as opened, so already rounded to its slot) with `text`.
    public init(sentAt: Date, text: String) {
        fingerprint = Self.fingerprint(sentAt: sentAt, text: text)
    }

    public static func fingerprint(sentAt: Date, text: String) -> UInt32 {
        let slot = Int((sentAt.timeIntervalSince(Frame.epoch) / Frame.slotSeconds).rounded(.down))
        var data = Data("dlchat-reply".utf8)
        data.append(0)
        data.append(Data(String(slot).utf8))
        data.append(0)
        data.append(Data(text.utf8))
        return SHA256.hash(data: data).prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    public var bits: Bits {
        var out = Bits()
        out.append(Self.marker, width: Self.markerBits)
        out.append(UInt64(fingerprint), width: Self.fingerprintBits)
        return out
    }

    /// The reference at bit `start` of an opened body, or nil when there is none (plain padding).
    public static func read(_ body: Bits, from start: Int) -> ReplyTo? {
        guard start >= 0, start + bitCount <= body.count,
              body.value(at: start, width: markerBits) == marker else { return nil }
        return ReplyTo(fingerprint: UInt32(body.value(at: start + markerBits, width: fingerprintBits)))
    }
}
