import Foundation

/// A group invite: `dlchat://join?name=Maple%20Street#word-word-word`. The phrase rides in the fragment.
/// The same text goes in the phrase QR code, so the system Camera can open DLChat on Join, and in the
/// optional message invite. Holding the link is holding the group key.
struct GroupInvite: Hashable {
    let phrase: String
    let name: String

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "dlchat"
        parts.host = "join"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.queryItems = [URLQueryItem(name: "name", value: trimmed)] }
        parts.fragment = phrase.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        return parts.url!
    }

    /// An invite link, or nil for anything else. The phrase is checked later by the normal join path.
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "dlchat", parts.host?.lowercased() == "join",
              let fragment = parts.fragment, !fragment.isEmpty else { return nil }
        phrase = fragment.split(separator: "-").joined(separator: " ")
        name = parts.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
    }

    init(phrase: String, name: String) {
        self.phrase = phrase
        self.name = name
    }

    /// Phrase text from a scanned code: an invite link, or the bare words that older codes held.
    static func phrase(fromCode code: String) -> String? {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let invite = GroupInvite(url: url) { return invite.phrase }
        return text.contains("://") ? nil : text
    }
}
