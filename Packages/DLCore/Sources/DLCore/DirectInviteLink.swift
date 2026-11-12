import CryptoKit
import Foundation

/// A short contact invite link: `dlchat://contact#<base64url(version + secret)>`, about 60 characters.
///
/// A full invite is about 1,260 bytes, almost all of it the ML-KEM-768 public key, which is random and
/// cannot be compressed. So the short link carries only the invite's 32-byte secret. The inviter seals the
/// full invite with a key that comes from that secret and posts it to a public-relay mailbox that also
/// comes from it; the other phone fetches it, opens it, and checks it holds the same secret. From there
/// the handshake is the full invite's, unchanged: the same keys and the same post-quantum first step.
///
/// The relay sees one padded, sealed blob in a mailbox nobody can link to the inviter, like the first
/// message that answers the invite. Holding the link is holding the invite, as with the full link.
public struct DirectInviteLink: Equatable, Sendable {
    public let secret: Data

    static let version: UInt8 = 1

    public init(secret: Data) { self.secret = secret }

    public var url: URL { URL(string: "dlchat://contact#" + (Data([Self.version]) + secret).base64URL)! }

    /// A short invite link (or the same text from a QR code), or nil for anything else, full links included.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "dlchat",
              parts.host?.lowercased() == "contact", let fragment = parts.fragment,
              let data = Data(base64URL: fragment), data.count == 33, data.first == Self.version else { return nil }
        secret = Data(data.dropFirst())
    }

    var sealKey: Data { DirectKDF.hkdf(secret, info: "DLChat/direct/v1/invite-link-seal") }
    var mailboxRoot: Data { DirectKDF.hkdf(secret, info: "DLChat/direct/v1/invite-link-mailbox") }
}

/// A contact invite as text: the full link (or QR code), or a short link whose invite is on the relays.
public enum DirectInviteText: Equatable, Sendable {
    case full(DirectInvite)
    case short(DirectInviteLink)

    public init?(text: String) {
        if let invite = DirectInvite(text: text) { self = .full(invite) }
        else if let link = DirectInviteLink(text: text) { self = .short(link) }
        else { return nil }
    }

    public var url: URL {
        switch self {
        case .full(let invite): invite.url
        case .short(let link): link.url
        }
    }
}

extension DirectInvite {
    /// The short link for this invite. It works only once `Direct.linkEvent(for:)` is on the relays.
    public var link: DirectInviteLink { DirectInviteLink(secret: secret) }
}

extension Direct {
    /// The full invite, sealed for its short link's mailbox. It expires with the invite.
    public static func linkEvent(for invite: DirectInvite, now: Date = Date()) throws -> Online.Event {
        let link = invite.link
        return try Online.wrap(content: try seal(invite.encoded, key: link.sealKey).base64EncodedString(),
                               to: mailbox(root: link.mailboxRoot, on: now), lifetime: DirectInvite.lifetime, now: now)
    }

    /// Mailboxes where a short link's invite may be: tomorrow, today and yesterday.
    public static func linkMailboxes(_ link: DirectInviteLink, now: Date = Date()) -> [String] {
        mailboxes(root: link.mailboxRoot, now: now, days: 2)
    }

    /// The invite inside a genuine event for this short link, or nil. It must hold the link's secret.
    public static func invite(from event: Online.Event, link: DirectInviteLink) -> DirectInvite? {
        guard event.kind == Online.kind, event.isValid, let bytes = Data(base64Encoded: event.content),
              let plain = try? open(bytes, key: link.sealKey), let invite = try? DirectInvite(encoded: plain),
              invite.secret == link.secret else { return nil }
        return invite
    }
}
