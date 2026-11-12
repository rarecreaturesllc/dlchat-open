/// The numbered boxes a friend types a picture invite's password into: one word per box, in the order
/// the sender read them out (box 1 first). Joining the boxes gives the same string the sender's words
/// make, so the password format and every existing picture are unchanged.
public struct PicturePasswordSlots: Equatable, Sendable {
    /// Five or six boxes; the friend picks which, since nothing in the picture says.
    public private(set) var words: [String]

    public init(count: Int = PictureInvite.passwordWordCounts.lowerBound) {
        words = Array(repeating: "", count: Self.clamp(count))
    }

    public var count: Int { words.count }

    /// The password to try: the filled boxes in order, so an older 4-word picture opens with four boxes
    /// filled and the last left empty.
    public var password: String { PictureInvite.normalizePassword(words.joined(separator: " ")) }

    public var isEmpty: Bool { password.isEmpty }

    /// Five or six boxes. Going down drops the last word; going up adds an empty box.
    public mutating func resize(to count: Int) {
        let count = Self.clamp(count)
        if count < words.count { words.removeLast(words.count - count) }
        else { words += Array(repeating: "", count: count - words.count) }
    }

    /// What the friend typed or pasted into box `index`. One word stays in that box. A space, or a pasted
    /// run of words, fills that box and the ones after it, adding the sixth box if six words arrive.
    /// Returns the box to move to, or nil to stay put.
    @discardableResult
    public mutating func enter(_ text: String, at index: Int) -> Int? {
        guard words.indices.contains(index) else { return nil }
        let found = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let endsWithGap = text.last.map { !$0.isLetter } ?? false
        guard found.count > 1 || (found.count == 1 && endsWithGap) else {
            words[index] = found.first ?? ""
            return nil
        }
        let last = PictureInvite.passwordWordCounts.upperBound - 1
        if index + found.count > words.count { resize(to: index + found.count) }
        for (offset, word) in found.enumerated() {
            let box = min(index + offset, last)
            // More words than boxes: keep the extras in the last box rather than losing them.
            words[box] = index + offset > last ? words[box] + " " + word : word
        }
        let filledUpTo = min(index + found.count - 1, words.count - 1)
        if endsWithGap, filledUpTo + 1 < words.count { return filledUpTo + 1 }
        return filledUpTo
    }

    private static func clamp(_ count: Int) -> Int {
        min(max(count, PictureInvite.passwordWordCounts.lowerBound), PictureInvite.passwordWordCounts.upperBound)
    }
}
