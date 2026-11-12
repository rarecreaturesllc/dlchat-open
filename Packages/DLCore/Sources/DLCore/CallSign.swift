import Foundation

/// A person's call sign: 1 to 4 letters or digits and one of eight colours, chosen in Settings and
/// shown on their Chat messages so friends can tell who wrote what.
///
/// It travels only inside the sealed Chat body, after the text (and after a carried frame), so relays
/// and radios never see it. Older versions read that part as padding and ignore it. On the wire:
/// a 16-bit marker, the letter count less one (2 bits), each letter (6 bits: A-Z then 0-9), the
/// colour (3 bits). Three letters cost 39 bits, about 5 bytes.
///
/// Anyone with the group phrase can pick any call sign, so it says who a message claims to be from,
/// not who sent it. A message from an older version whose random padding happens to start with the
/// marker could show a stray call sign: about 1 in 65,536 of its shortest messages.
public struct CallSign: Codable, Equatable, Hashable {
    public static let maxLetters = 4
    public static let colors = 8
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    /// First 8 bits are zero, so a plain message reading "dlwords" never mistakes it for a carried frame's word count.
    static let marker: UInt64 = 0x00C5
    static let markerBits = 16

    public let letters: String
    /// 0..<8; the app maps it to a colour.
    public let color: Int

    /// Nil when nothing usable is left. Lowercase is raised; anything not A-Z or 0-9 is dropped;
    /// more than four characters are cut to four.
    public init?(_ text: String, color: Int = 0) {
        let kept = Self.clean(text)
        guard !kept.isEmpty, (0..<Self.colors).contains(color) else { return nil }
        letters = kept
        self.color = color
    }

    /// What a typed call sign becomes: uppercased, A-Z and 0-9 only, at most four.
    public static func clean(_ text: String) -> String {
        String(text.uppercased().filter { alphabet.contains($0) }.prefix(maxLetters))
    }

    public var bits: Bits {
        var out = Bits()
        out.append(Self.marker, width: Self.markerBits)
        out.append(UInt64(letters.count - 1), width: 2)
        for ch in letters { out.append(UInt64(Self.alphabet.firstIndex(of: ch) ?? 0), width: 6) }
        out.append(UInt64(color), width: 3)
        return out
    }

    /// The call sign at bit `start` of an opened body, or nil when there is none (plain padding).
    public static func read(_ body: Bits, from start: Int) -> CallSign? {
        guard start >= 0, start + markerBits + 2 <= body.count,
              body.value(at: start, width: markerBits) == marker else { return nil }
        let count = Int(body.value(at: start + markerBits, width: 2)) + 1
        var position = start + markerBits + 2
        guard position + count * 6 + 3 <= body.count else { return nil }
        var letters = ""
        for _ in 0..<count {
            let index = Int(body.value(at: position, width: 6))
            guard index < alphabet.count else { return nil }
            letters.append(alphabet[index])
            position += 6
        }
        return CallSign(letters, color: Int(body.value(at: position, width: 3)))
    }
}
