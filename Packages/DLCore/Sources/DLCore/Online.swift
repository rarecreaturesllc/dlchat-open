import CryptoKit
import Foundation
import P256K

/// DLChat over Nostr relays (evolve/ONLINE_MODE.md). A relay carries the same sealed frame Nearby
/// sends, wrapped once more under a group key and padded, inside an ordinary-looking gift-wrap event
/// (kind 1059) signed by a throwaway key and addressed to the group's mailbox for that day.
/// The relay learns: a post to a random-looking key that changes daily, a size bucket, a blurred time.
public enum Online {
    public static let kind = 1059
    /// Relays are asked to delete events after this (NIP-40); they may not.
    public static let lifetime: TimeInterval = 14 * 86_400
    /// How far back `created_at` is blurred, like NIP-17.
    static let blur: TimeInterval = 2 * 86_400
    /// Wrapped sizes: the content length only says which bucket.
    static let buckets = [256, 512, 1024, 2048]

    // MARK: Group secrets

    struct GroupSecrets {
        let mailboxRoot: SymmetricKey
        let wrapKey: SymmetricKey
        init(_ keys: Keys) {
            // From the group master, not the room: one mailbox per group, rooms sort themselves out on opening.
            mailboxRoot = Keys.hkdf(keys.master, info: "online/mailbox")
            wrapKey = Keys.hkdf(keys.master, info: "online/wrap")
        }
    }

    static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The group's mailbox (an x-only public key, hex) for the UTC day of `date`.
    public static func mailbox(for keys: Keys, on date: Date) -> String {
        hex(mailboxKey(for: keys, on: date).xonly.bytes)
    }

    static func mailboxKey(for keys: Keys, on date: Date) -> P256K.Schnorr.PrivateKey {
        let secret = HMAC<CryptoKit.SHA256>.authenticationCode(for: Data("DLChat/v1/mailbox \(dayString(date))".utf8),
                                                    using: GroupSecrets(keys).mailboxRoot)
        // A 32-byte HMAC is a valid secp256k1 scalar except with negligible probability.
        return try! P256K.Schnorr.PrivateKey(dataRepresentation: Data(secret))
    }

    /// NIP-42 sign-in events, one per watched mailbox, so a relay that guards gift wraps (Damus) serves
    /// a mailbox's events only to whoever holds its key. Never published; sent only in reply to AUTH.
    public static func authEvents(challenge: String, relay: URL, keys: [Keys], now: Date = Date(), days: Int = 15) throws -> [Event] {
        try keys.flatMap { groupKeys in
            try (-1..<days).map { offset in
                let key = mailboxKey(for: groupKeys, on: now.addingTimeInterval(-Double(offset) * 86_400))
                var event = Event(id: "", pubkey: hex(key.xonly.bytes), createdAt: Int(now.timeIntervalSince1970), kind: 22242,
                                  tags: [["relay", relay.absoluteString], ["challenge", challenge]], content: "", sig: "")
                let digest = HashDigest(Array(CryptoKit.SHA256.hash(data: Data(event.serialized.utf8))))
                event.id = hex(Array(digest))
                event.sig = hex(Array(try key.signature(for: digest).dataRepresentation))
                return event
            }
        }
    }

    /// Mailboxes to watch: tomorrow (a sender's clock may run ahead) back to `days` ago.
    public static func mailboxes(for keys: Keys, now: Date, days: Int = 15) -> [String] {
        (-1..<days).map { mailbox(for: keys, on: now.addingTimeInterval(-Double($0) * 86_400)) }
    }

    // MARK: Events

    /// A sealed Nearby wire message (hop byte + frame) as a signed event for the group's mailbox today.
    public static func event(wire: Data, keys: Keys, now: Date = Date()) throws -> Event {
        let secrets = GroupSecrets(keys)
        var plain = [UInt8(wire.count >> 8), UInt8(wire.count & 0xFF)] + Array(wire)
        guard let size = buckets.first(where: { $0 >= plain.count + 28 }) else { throw OnlineError.tooLarge }
        plain += [UInt8](repeating: 0, count: size - 28 - plain.count)
        let box = try ChaChaPoly.seal(plain, using: secrets.wrapKey)
        return try wrap(content: box.combined.base64EncodedString(), to: mailbox(for: keys, on: now), lifetime: lifetime, now: now)
    }

    /// `content` as a gift-wrap event for `mailbox`, signed by a throwaway key with a blurred time.
    static func wrap(content: String, to mailbox: String, lifetime: TimeInterval, now: Date) throws -> Event {
        let author = try P256K.Schnorr.PrivateKey()  // throwaway: nothing links two posts
        let created = Int(now.timeIntervalSince1970 - Double.random(in: 0...blur))
        // Expiry counts from the blurred time, so it does not give the real send time away; it still
        // lands at least `lifetime` after sending.
        let tags = [["p", mailbox], ["expiration", String(created + Int(lifetime + blur))]]
        var event = Event(id: "", pubkey: hex(author.xonly.bytes), createdAt: created, kind: kind, tags: tags,
                          content: content, sig: "")
        let digest = HashDigest(Array(CryptoKit.SHA256.hash(data: Data(event.serialized.utf8))))
        event.id = hex(Array(digest))
        event.sig = hex(Array(try author.signature(for: digest).dataRepresentation))
        return event
    }

    /// The Nearby wire message inside an event, if it is genuine and one of these groups can unwrap it.
    /// Returns the wire bytes and the index of the group's keys.
    public static func wire(from event: Event, trying keys: [Keys]) -> (wire: Data, keysIndex: Int)? {
        guard event.kind == kind, event.isValid, let combined = Data(base64Encoded: event.content) else { return nil }
        for (index, groupKeys) in keys.enumerated() {
            guard let box = try? ChaChaPoly.SealedBox(combined: combined),
                  let plain = try? ChaChaPoly.open(box, using: GroupSecrets(groupKeys).wrapKey) else { continue }
            let bytes = [UInt8](plain)
            guard bytes.count >= 2 else { return nil }
            let length = Int(bytes[0]) << 8 | Int(bytes[1])
            guard length > 0, 2 + length <= bytes.count else { return nil }
            return (Data(bytes[2..<(2 + length)]), index)
        }
        return nil
    }

    /// A NIP-01 subscription filter for these mailboxes.
    public static func filter(mailboxes: [String], since: Date) -> [String: Any] {
        ["kinds": [kind], "#p": mailboxes, "since": Int(since.timeIntervalSince1970)]
    }

    // MARK: Event

    public struct Event: Equatable {
        public var id: String
        public let pubkey: String
        public let createdAt: Int
        public let kind: Int
        public let tags: [[String]]
        public let content: String
        public var sig: String

        /// NIP-01 serialization for the id: `[0,pubkey,created_at,kind,tags,content]`, no spaces.
        var serialized: String {
            let tagList = tags.map { "[" + $0.map(quote).joined(separator: ",") + "]" }.joined(separator: ",")
            return "[0,\(quote(pubkey)),\(createdAt),\(kind),[\(tagList)],\(quote(content))]"
        }

        /// The id is the hash of the content and the signature is the author's.
        public var isValid: Bool {
            let digest = HashDigest(Array(CryptoKit.SHA256.hash(data: Data(serialized.utf8))))
            guard hex(Array(digest)) == id, let keyBytes = unhex(pubkey), keyBytes.count == 32,
                  let sigBytes = unhex(sig), let signature = try? P256K.Schnorr.SchnorrSignature(dataRepresentation: sigBytes)
            else { return false }
            return P256K.Schnorr.XonlyKey(dataRepresentation: keyBytes).isValidSignature(signature, for: digest)
        }

        public var json: [String: Any] {
            ["id": id, "pubkey": pubkey, "created_at": createdAt, "kind": kind, "tags": tags, "content": content, "sig": sig]
        }

        public init(id: String, pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String, sig: String) {
            self.id = id; self.pubkey = pubkey; self.createdAt = createdAt; self.kind = kind
            self.tags = tags; self.content = content; self.sig = sig
        }

        public init?(json: [String: Any]) {
            guard let id = json["id"] as? String, let pubkey = json["pubkey"] as? String,
                  let created = json["created_at"] as? Int, let kind = json["kind"] as? Int,
                  let tags = json["tags"] as? [[String]], let content = json["content"] as? String,
                  let sig = json["sig"] as? String else { return nil }
            self.init(id: id, pubkey: pubkey, createdAt: created, kind: kind, tags: tags, content: content, sig: sig)
        }
    }
}

public enum OnlineError: Error { case tooLarge }

/// NIP-01 string escaping: \n \" \\ \r \t \b \f; everything else as is.
func quote(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\n": out += "\\n"
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func unhex(_ s: String) -> [UInt8]? {
    guard s.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var index = s.startIndex
    while index < s.endIndex {
        let next = s.index(index, offsetBy: 2)
        guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
        out.append(byte)
        index = next
    }
    return out
}
