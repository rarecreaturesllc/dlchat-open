import CryptoKit
import Foundation
import P256K

/// Settings → Send anonymously (owner request 2026-11-08): a bug report the person writes, sealed so only
/// the developer can read it, and posted through Tor the way a group message is. HPKE (RFC 9180: X25519,
/// HKDF-SHA256, ChaCha20-Poly1305) to the developer's public key, padded to a size bucket, inside a
/// kind-1059 event from a throwaway key with a blurred time, addressed to one fixed support mailbox.
/// A relay sees an ordinary gift wrap: it cannot read it or tell who sent it. There is no reply path.
public enum SupportReport {
    /// The developer's X25519 public key. Its private key is in the developer's Mac Keychain
    /// ("DLChat support key") and never ships.
    public static let developerKey = "WMSzkr/EiKy3lpUdWrptcGwDwKhvvDwoAXe4KpFlsXs="
    static let info = Data("DLChat/v1/support".utf8)
    /// Relays are asked to keep reports a month (NIP-40), so a weekly read misses none.
    public static let lifetime: TimeInterval = 30 * 86_400
    /// Padded plaintext sizes: the content length only says which bucket.
    static let buckets = [1024, 4096]

    /// The support mailbox: a fixed, well-formed x-only key (hex). Its private key is derived from a
    /// constant, so anyone can find these posts, but only the developer's key opens them.
    public static let mailbox: String = {
        let seed = Data(CryptoKit.SHA256.hash(data: Data("DLChat/v1/support mailbox".utf8)))
        // A SHA-256 output is a valid secp256k1 scalar except with negligible probability (tests pin it).
        return hex(try! P256K.Schnorr.PrivateKey(dataRepresentation: seed).xonly.bytes)
    }()

    /// The sealed report as a signed event. Throws `OnlineError.tooLarge` past the largest bucket.
    public static func event(text: String, now: Date = Date(), recipient: String = developerKey) throws -> Online.Event {
        let bytes = Array(text.utf8)
        var plain = [UInt8(bytes.count >> 8 & 0xFF), UInt8(bytes.count & 0xFF)] + bytes
        guard let size = buckets.first(where: { $0 >= plain.count }) else { throw OnlineError.tooLarge }
        plain += [UInt8](repeating: 0, count: size - plain.count)
        let key = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: recipient) ?? Data())
        var sender = try HPKE.Sender(recipientKey: key, ciphersuite: .Curve25519_SHA256_ChachaPoly, info: info)
        let sealed = try sender.seal(plain)
        return try Online.wrap(content: (sender.encapsulatedKey + sealed).base64EncodedString(), to: mailbox,
                               lifetime: lifetime, now: now)
    }

    /// The report text, if the event is genuine and `privateKey` opens it.
    public static func text(from event: Online.Event, privateKey: Curve25519.KeyAgreement.PrivateKey) -> String? {
        guard event.kind == Online.kind, event.isValid, let combined = Data(base64Encoded: event.content),
              combined.count > 32,
              var recipient = try? HPKE.Recipient(privateKey: privateKey, ciphersuite: .Curve25519_SHA256_ChachaPoly,
                                                  info: info, encapsulatedKey: combined.prefix(32)),
              let plain = try? recipient.open(combined.dropFirst(32)) else { return nil }
        let bytes = [UInt8](plain)
        guard bytes.count >= 2 else { return nil }
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        guard 2 + length <= bytes.count else { return nil }
        return String(decoding: bytes[2..<(2 + length)], as: UTF8.self)
    }

    /// A NIP-01 filter for the support mailbox.
    public static func filter(since: Date) -> [String: Any] {
        Online.filter(mailboxes: [mailbox], since: since)
    }
}
