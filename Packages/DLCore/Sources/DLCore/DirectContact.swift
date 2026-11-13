import CryptoKit
import Foundation
import P256K

/// Which way Internet Messages travel (Settings > Internet Messaging). Each person picks for their own
/// incoming messages; a sender always uses the way the receiver picked.
public enum DirectRoute: String, Codable, CaseIterable, Sendable {
    /// Option B: DLChat's own relays, reachable only as Tor onion services. The default.
    case privateRelays
    /// Option A: public Nostr relays, the same ones group chats use.
    case publicRelays
    /// Both at once: most reliable, but the public relays see timing too.
    case both

    var flag: UInt8 { switch self { case .privateRelays: 1; case .publicRelays: 2; case .both: 3 } }
    init?(flag: UInt8) {
        switch flag { case 1: self = .privateRelays; case 2: self = .publicRelays; case 3: self = .both; default: return nil }
    }
    public var usesPrivate: Bool { self != .publicRelays }
    public var usesPublic: Bool { self != .privateRelays }
}

/// Where someone can be sent to on a private relay: the relay's onion address and the send end of
/// one queue that only they can read.
public struct OnionQueue: Codable, Equatable, Hashable, Sendable {
    public let relay: String
    public let sendID: String
    public init(relay: String, sendID: String) { self.relay = relay; self.sendID = sendID }
}

/// A queue this phone reads on a private relay: both ends' ids and the Ed25519 key that signs reads.
public struct OwnQueue: Codable, Equatable, Sendable {
    public let relay: String
    public let recvID: String
    public let sendID: String
    public let signingKey: Data
    public init(relay: String, recvID: String, sendID: String, signingKey: Data) {
        self.relay = relay; self.recvID = recvID; self.sendID = sendID; self.signingKey = signingKey
    }
    public var address: OnionQueue { OnionQueue(relay: relay, sendID: sendID) }

    /// A new Ed25519 key for a queue: (private to keep, public to give the relay).
    public static func newSigningKey() -> (privateKey: Data, publicKey: Data) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation, key.publicKey.rawRepresentation)
    }

    /// The signed body of a read, acknowledge or delete request (see relay/handler.go).
    public func signedRequest(_ action: String, now: Date = Date(), extra: [String: Any] = [:]) throws -> [String: Any] {
        let ts = Int(now.timeIntervalSince1970)
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKey)
        let signature = try key.signature(for: Data("dlchat-relay/v1/\(action)|\(recvID)|\(ts)".utf8))
        var body: [String: Any] = ["ts": ts, "sig": signature.map { String(format: "%02x", $0) }.joined()]
        for (k, v) in extra { body[k] = v }
        return body
    }
}

// MARK: Invite

/// A one-time contact invite: `dlchat://contact#<base64url>`, shown as a QR code or sent as a link.
/// Whoever opens it first becomes the contact; both phones then show the same safety words,
/// which the two people read to each other to be sure nobody else took it.
public struct DirectInvite: Equatable, Sendable {
    public let identity: Data      // X25519, also the first ratchet key
    public let kemPublic: Data     // ML-KEM-768
    public let secret: Data        // 32 random bytes: the invite's mailbox and wrap key come from it
    public let route: DirectRoute
    public let onion: OnionQueue?
    public let name: String
    /// What the inviter's build can do. 1: builds up to 28 (six safety words from the two identity keys).
    /// 2: eight safety words that cover the whole invite, and a contact secret with the ML-KEM secret mixed in.
    /// It travels as one byte after the name, which older builds ignore; an invite without it is version 1.
    ///
    /// Nothing protects the byte, and it cannot while older builds must still be answered: someone able to
    /// change an invite on its way can cut it off, and both phones then show the six words of version 1,
    /// which is no worse than builds up to 28 but no better. Eight words mean both phones checked the whole
    /// invite; six mean they did not. Refuse version 1 once no supported build makes it.
    public let version: UInt8

    static let magic = Data("DLC1".utf8)
    public static let currentVersion: UInt8 = 2
    public static let lifetime: TimeInterval = 24 * 3600
    public static let maxName = 40

    public var encoded: Data {
        var w = ByteWriter()
        w.bytes(Self.magic)
        w.bytes(identity)
        w.bytes(kemPublic)
        w.bytes(secret)
        w.u8(route.flag)
        w.field(Data((onion?.relay ?? "").utf8))
        w.field(Data((onion?.sendID ?? "").utf8))
        w.field(Data(Self.trim(name).utf8))
        if version >= 2 { w.u8(version) }
        return w.data
    }

    public var url: URL { URL(string: "dlchat://contact#" + encoded.base64URL)! }

    public init(identity: Data, kemPublic: Data, secret: Data, route: DirectRoute, onion: OnionQueue?, name: String,
                version: UInt8 = DirectInvite.currentVersion) {
        self.identity = identity; self.kemPublic = kemPublic; self.secret = secret
        self.route = route; self.onion = onion; self.name = Self.trim(name)
        self.version = Self.known(version)
    }

    /// Versions this build does not know count as the newest one it does.
    static func known(_ version: UInt8) -> UInt8 { min(max(version, 1), currentVersion) }

    /// What the version 2 safety words cover: a hash of every field of the invite (both keys, the secret,
    /// the route, the queue and the name), taken from the invite as this build writes it, so the inviter
    /// and whoever opened it hash the same bytes. A changed or swapped field changes the words.
    var safetyBinding: Data {
        let canonical = (try? DirectInvite(encoded: encoded))?.encoded ?? encoded
        return Data(SHA256.hash(data: Data("DLChat/direct/v2/invite".utf8) + canonical))
    }

    public init(encoded: Data) throws {
        var r = ByteReader(encoded)
        guard try r.bytes(4) == Self.magic else { throw DirectError.malformed }
        identity = try r.bytes(32)
        kemPublic = try r.bytes(PQ.publicKeySize)
        secret = try r.bytes(32)
        guard let route = DirectRoute(flag: try r.u8()) else { throw DirectError.malformed }
        self.route = route
        let relay = String(decoding: try r.field(), as: UTF8.self)
        let send = String(decoding: try r.field(), as: UTF8.self)
        onion = relay.isEmpty || send.isEmpty ? nil : OnionQueue(relay: relay, sendID: send)
        name = Self.trim(String(decoding: try r.field(), as: UTF8.self))
        version = r.remaining >= 1 ? Self.known(try r.u8()) : 1
    }

    /// A contact invite link (or the same text from a QR code), or nil for anything else.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "dlchat",
              parts.host?.lowercased() == "contact", let fragment = parts.fragment,
              let data = Data(base64URL: fragment), let invite = try? DirectInvite(encoded: data) else { return nil }
        self = invite
    }

    static func trim(_ name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        for ch in clean where (out + String(ch)).utf8.count <= maxName { out.append(ch) }
        return out
    }

    /// The key that seals the first message to the inviter, and the inviter's mailbox root for it.
    var wrapKey: Data { DirectKDF.hkdf(secret, info: "DLChat/direct/v1/invite-wrap") }
    var mailboxRoot: Data { DirectKDF.hkdf(secret, info: "DLChat/direct/v1/invite-mailbox") }
}

/// What the inviter keeps until the invite is used once or expires.
public struct PendingInvite: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let identityPrivate: Data
    public let identityPublic: Data
    public let kemSeed: Data
    public let kemPublic: Data
    public let secret: Data
    public let route: DirectRoute
    public let queue: OwnQueue?
    public let name: String
    public let created: Date

    public var invite: DirectInvite {
        DirectInvite(identity: identityPublic, kemPublic: kemPublic, secret: secret, route: route, onion: queue?.address, name: name)
    }

    public func isExpired(now: Date = Date()) -> Bool { now.timeIntervalSince(created) > DirectInvite.lifetime }

    /// A new invite. `queue`: this phone's queue on a private relay, when private relays are in use.
    public static func make(name: String, route: DirectRoute, queue: OwnQueue?, now: Date = Date()) throws -> PendingInvite {
        let identity = DirectKDF.newX25519()
        let kem = try PQ.generate()
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return PendingInvite(id: UUID(), identityPrivate: identity.privateKey, identityPublic: identity.publicKey,
                             kemSeed: kem.seed, kemPublic: kem.publicKey, secret: secret, route: route, queue: queue,
                             name: DirectInvite.trim(name), created: now)
    }
}

// MARK: Contact

/// One Internet Messages contact: the ratchet, where to send, and where this phone listens.
public struct DirectContact: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    /// Our identity for this contact only (a fresh key per contact, so two contacts cannot tell they
    /// talk to the same person), and theirs.
    let identityPublic: Data
    public let theirIdentity: Data
    var ratchet: DirectRatchet
    /// Fixed per contact: the outer wrap key and the mailbox roots come from it.
    let contactSecret: Data
    /// What each side picked for its own incoming messages.
    public var myRoute: DirectRoute
    public var theirRoute: DirectRoute
    public var theirQueue: OnionQueue?
    public var myQueue: OwnQueue?
    public let created: Date
    /// The pending invite this contact came from (inviter side), so a second copy of the first message is ignored.
    public let inviteID: UUID?
    /// `DirectInvite.safetyBinding` of the invite this contact came from, when both phones run a build
    /// that knows version 2. Nil for contacts made with or by an older build: those keep the six words.
    var safetyBinding: Data? = nil

    /// List words both phones show; read them to each other once.
    ///
    /// Version 2 (both phones on build 29 or later): eight words, 80 bits, from both identity keys and a
    /// hash of the whole invite. Whoever answers an invite picks their key after seeing the inviter's, so
    /// someone who took the invite could try keys until the words matched: 60 bits is within reach of a very
    /// well funded attacker inside the invite's 24 hours, 80 is not. Covering the invite means a swapped
    /// ML-KEM key (the one part a future quantum computer in the middle could change unseen) changes the words.
    ///
    /// Version 1 (either phone on an older build): the six words builds 18 to 28 showed, from the two
    /// identity keys alone. Their first three are the words builds up to 17 showed.
    public var safetyWords: [String] {
        let pair = [identityPublic, theirIdentity].sorted { $0.lexicographicallyPrecedes($1) }
        if let safetyBinding {
            let digest = Array(SHA256.hash(data: Data("DLChat/direct/v2/safety".utf8) + pair[0] + pair[1] + safetyBinding))
            let bits = Bits(bytes: digest, count: 80)
            return (0..<8).map { WordList.word(at: Int(bits.value(at: $0 * 10, width: 10))) }
        }
        let digest = Array(SHA256.hash(data: Data("DLChat/direct/v1/safety".utf8) + pair[0] + pair[1]))
        let value = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return [54, 44, 34, 24, 14, 4].map { WordList.word(at: Int((value >> UInt64($0)) & 1023)) }
    }

    var wrapKey: Data { DirectKDF.hkdf(contactSecret, info: "DLChat/direct/v1/wrap") }

    /// The Nostr mailbox root for messages *from* the holder of `senderIdentity`.
    func mailboxRoot(from senderIdentity: Data) -> Data {
        DirectKDF.hkdf(contactSecret, salt: senderIdentity, info: "DLChat/direct/v1/mailbox")
    }

    /// Mailboxes this phone reads (messages from them), tomorrow back to `days` ago.
    public func incomingMailboxes(now: Date = Date(), days: Int = 15) -> [String] {
        Direct.mailboxes(root: mailboxRoot(from: theirIdentity), now: now, days: days)
    }

    /// Where messages to them go when they use public relays.
    func outgoingMailbox(now: Date) -> String { Direct.mailbox(root: mailboxRoot(from: identityPublic), on: now) }

    static func sharedSecrets(dh: Data, inviteSecret: Data) -> (ratchet: Data, contact: Data) {
        let sk = DirectKDF.hkdf(dh, salt: inviteSecret, info: "DLChat/direct/v1/sk")
        return (DirectKDF.hkdf(sk, info: "DLChat/direct/v1/ratchet"), DirectKDF.hkdf(sk, info: "DLChat/direct/v1/contact"))
    }

    /// Version 2: the contact secret (outer wrap key and mailbox addresses) also takes the first ML-KEM
    /// secret, so someone who later breaks X25519 and holds the invite still cannot work out the mailboxes.
    static func contactSecretV2(classical: Data, kemSecret: Data) -> Data {
        DirectKDF.hkdf(classical + kemSecret, info: "DLChat/direct/v2/contact")
    }
}

// MARK: Messages

/// What one Internet Message holds once opened.
public struct DirectMessage: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case text = 1, hello = 2 }
    public let kind: Kind
    public let id: Data          // 16 random bytes, so copies by two routes are one message
    public let sentAt: Date
    public let text: String

    public static let maxTextBytes = 4000

    public init(kind: Kind = .text, text: String, sentAt: Date = Date(), id: Data? = nil) {
        self.kind = kind
        self.text = text
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(Int(sentAt.timeIntervalSince1970)))
        if let id { self.id = id } else {
            self.id = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        }
    }

    var encoded: Data {
        var w = ByteWriter()
        w.u8(kind.rawValue)
        w.bytes(id)
        w.u32(UInt32(max(0, sentAt.timeIntervalSince1970)))
        w.bytes(Data(text.utf8))
        return w.data
    }

    init(encoded: Data) throws {
        var r = ByteReader(encoded)
        guard let kind = Kind(rawValue: try r.u8()) else { throw DirectError.malformed }
        self.kind = kind
        id = try r.bytes(16)
        sentAt = Date(timeIntervalSince1970: TimeInterval(try r.u32()))
        text = String(decoding: r.rest(), as: UTF8.self)
    }
}

/// The sealed bytes that travel, by either route.
public struct DirectEnvelope: Equatable, Sendable {
    public let bytes: Data
    /// Same bytes by two routes: one message.
    public var fingerprint: String { SHA256.hash(data: bytes).prefix(16).map { String(format: "%02x", $0) }.joined() }
    public init(bytes: Data) { self.bytes = bytes }
}

public enum Direct {
    /// Sealed sizes: the length only says which bucket.
    static let buckets = [4096, 8192, 16384]
    /// `helloTag`: a first message from a build up to 28, or to an invite made by one. `helloV2Tag`: the
    /// same bytes from a build that knows version 2, answering a version 2 invite. Older builds refuse it,
    /// which is why it is only sent to an invite that says its maker understands it.
    static let helloTag: UInt8 = 1, messageTag: UInt8 = 2, helloV2Tag: UInt8 = 3

    // MARK: Handshake

    /// Accepting an invite: the new contact and the first message, sealed for the inviter.
    public static func accept(_ invite: DirectInvite, myName: String, myRoute: DirectRoute, myQueue: OwnQueue?,
                              now: Date = Date()) throws -> (DirectContact, DirectEnvelope) {
        let identity = DirectKDF.newX25519()
        let secrets = DirectContact.sharedSecrets(dh: try DirectKDF.dh(identity.privateKey, invite.identity), inviteSecret: invite.secret)
        let started = try DirectRatchet.initiatorWithSecret(sharedSecret: secrets.ratchet, theirRatchet: invite.identity,
                                                            theirKEM: invite.kemPublic)
        var ratchet = started.ratchet
        let kemSecret = started.kemSecret
        let first = try ratchet.encrypt(DirectMessage(kind: .hello, text: DirectInvite.trim(myName), sentAt: now).encoded)
        let v2 = invite.version >= 2
        var w = ByteWriter()
        w.u8(v2 ? helloV2Tag : helloTag)
        w.bytes(identity.publicKey)
        w.u8(myRoute.flag)
        w.field(Data((myQueue?.relay ?? "").utf8))
        w.field(Data((myQueue?.sendID ?? "").utf8))
        w.bytes(first)
        let contact = DirectContact(id: UUID(), name: invite.name.isEmpty ? "New contact" : invite.name,
                                    identityPublic: identity.publicKey, theirIdentity: invite.identity, ratchet: ratchet,
                                    contactSecret: v2 ? DirectContact.contactSecretV2(classical: secrets.contact, kemSecret: kemSecret)
                                                      : secrets.contact,
                                    myRoute: myRoute, theirRoute: invite.route,
                                    theirQueue: invite.onion, myQueue: myQueue, created: now, inviteID: nil,
                                    safetyBinding: v2 ? invite.safetyBinding : nil)
        return (contact, DirectEnvelope(bytes: try seal(w.data, key: invite.wrapKey)))
    }

    /// The inviter opening a first message: the new contact and the hello (its text is the other side's name).
    public static func openHello(_ envelope: DirectEnvelope, pending: PendingInvite, now: Date = Date()) throws -> (DirectContact, DirectMessage) {
        guard !pending.isExpired(now: now) else { throw DirectError.expiredInvite }
        let payload = try open(envelope.bytes, key: pending.invite.wrapKey)
        var r = ByteReader(payload)
        let tag = try r.u8()
        guard tag == helloTag || tag == helloV2Tag else { throw DirectError.notForUs }
        let v2 = tag == helloV2Tag
        let theirIdentity = try r.bytes(32)
        guard let theirRoute = DirectRoute(flag: try r.u8()) else { throw DirectError.malformed }
        let relay = String(decoding: try r.field(), as: UTF8.self)
        let send = String(decoding: try r.field(), as: UTF8.self)
        let first = r.rest()
        let secrets = DirectContact.sharedSecrets(dh: try DirectKDF.dh(pending.identityPrivate, theirIdentity), inviteSecret: pending.secret)
        var ratchet = DirectRatchet.responder(sharedSecret: secrets.ratchet, ratchetPrivate: pending.identityPrivate,
                                              ratchetPublic: pending.identityPublic, kemSeed: pending.kemSeed, kemPublic: pending.kemPublic)
        let message = try DirectMessage(encoded: try ratchet.decrypt(first))
        guard message.kind == .hello else { throw DirectError.malformed }
        var contactSecret = secrets.contact
        if v2 {
            // The ML-KEM secret behind the first message, which the ratchet just checked by opening it.
            var header = ByteReader(first)
            guard let ciphertext = try DirectRatchet.Header.decode(&header).kemCiphertext else { throw DirectError.malformed }
            contactSecret = DirectContact.contactSecretV2(
                classical: secrets.contact, kemSecret: try PQ.decapsulate(seed: pending.kemSeed, ciphertext: ciphertext))
        }
        let name = DirectInvite.trim(message.text)
        let contact = DirectContact(id: UUID(), name: name.isEmpty ? "New contact" : name, identityPublic: pending.identityPublic,
                                    theirIdentity: theirIdentity, ratchet: ratchet, contactSecret: contactSecret,
                                    myRoute: pending.route, theirRoute: theirRoute,
                                    theirQueue: relay.isEmpty || send.isEmpty ? nil : OnionQueue(relay: relay, sendID: send),
                                    myQueue: pending.queue, created: now, inviteID: pending.id,
                                    safetyBinding: v2 ? pending.invite.safetyBinding : nil)
        return (contact, message)
    }

    // MARK: Messages

    /// Seals a message to a contact. The contact's ratchet moves on, so store the returned contact.
    public static func seal(_ message: DirectMessage, for contact: DirectContact) throws -> (DirectContact, DirectEnvelope) {
        guard Data(message.text.utf8).count <= DirectMessage.maxTextBytes else { throw DirectError.tooLarge }
        var updated = contact
        let body = try updated.ratchet.encrypt(message.encoded)
        return (updated, DirectEnvelope(bytes: try seal(Data([messageTag]) + body, key: contact.wrapKey)))
    }

    /// Opens an envelope from a contact; throws `notForUs` when it is not theirs.
    public static func open(_ envelope: DirectEnvelope, from contact: DirectContact) throws -> (DirectContact, DirectMessage) {
        let payload: Data
        do { payload = try open(envelope.bytes, key: contact.wrapKey) } catch { throw DirectError.notForUs }
        guard payload.first == messageTag else { throw DirectError.notForUs }
        var updated = contact
        let message = try DirectMessage(encoded: try updated.ratchet.decrypt(payload.dropFirst()))
        return (updated, message)
    }

    // MARK: Outer seal

    static func seal(_ payload: Data, key: Data) throws -> Data {
        var plain = ByteWriter()
        plain.u32(UInt32(payload.count))
        plain.bytes(payload)
        guard let size = buckets.first(where: { $0 >= plain.data.count + 28 }) else { throw DirectError.tooLarge }
        let padded = plain.data + Data(count: size - 28 - plain.data.count)
        return try ChaChaPoly.seal(padded, using: SymmetricKey(data: key)).combined
    }

    static func open(_ sealed: Data, key: Data) throws -> Data {
        let plain = try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: sealed), using: SymmetricKey(data: key))
        var r = ByteReader(plain)
        let length = Int(try r.u32())
        return try r.bytes(length)
    }

    // MARK: Public relays (Nostr)

    static func mailboxKey(root: Data, on date: Date) -> P256K.Schnorr.PrivateKey {
        let secret = HMAC<CryptoKit.SHA256>.authenticationCode(for: Data("DLChat/direct/v1/mailbox \(Online.dayString(date))".utf8),
                                                     using: SymmetricKey(data: root))
        // A 32-byte HMAC is a valid secp256k1 scalar except with negligible probability.
        return try! P256K.Schnorr.PrivateKey(dataRepresentation: Data(secret))
    }

    static func mailbox(root: Data, on date: Date) -> String { hex(mailboxKey(root: root, on: date).xonly.bytes) }

    static func mailboxes(root: Data, now: Date, days: Int) -> [String] {
        (-1..<days).map { mailbox(root: root, on: now.addingTimeInterval(-Double($0) * 86_400)) }
    }

    /// The inviter's mailboxes for first messages to this invite.
    public static func inviteMailboxes(_ pending: PendingInvite, now: Date = Date()) -> [String] {
        mailboxes(root: pending.invite.mailboxRoot, now: now, days: 2)
    }

    /// A gift-wrap event carrying an envelope to a contact's public-relay mailbox.
    public static func event(_ envelope: DirectEnvelope, to contact: DirectContact, now: Date = Date()) throws -> Online.Event {
        try Online.wrap(content: envelope.bytes.base64EncodedString(), to: contact.outgoingMailbox(now: now), lifetime: Online.lifetime, now: now)
    }

    /// A gift-wrap event carrying a first message to an invite's mailbox.
    public static func event(_ envelope: DirectEnvelope, toInvite invite: DirectInvite, now: Date = Date()) throws -> Online.Event {
        try Online.wrap(content: envelope.bytes.base64EncodedString(), to: mailbox(root: invite.mailboxRoot, on: now),
                        lifetime: 2 * 86_400, now: now)
    }

    /// Today's mailbox for first messages to an invite.
    public static func inviteMailbox(_ invite: DirectInvite, now: Date = Date()) -> String { mailbox(root: invite.mailboxRoot, on: now) }

    /// Today's public-relay mailbox for messages to a contact.
    public static func outgoingMailbox(_ contact: DirectContact, now: Date = Date()) -> String { contact.outgoingMailbox(now: now) }

    /// A gift-wrap event carrying an envelope to a mailbox chosen earlier (a queued message keeps its mailbox).
    public static func event(_ envelope: DirectEnvelope, mailbox: String, now: Date = Date()) throws -> Online.Event {
        try Online.wrap(content: envelope.bytes.base64EncodedString(), to: mailbox, lifetime: Online.lifetime, now: now)
    }

    /// The envelope inside a genuine event, and the mailbox it was addressed to.
    public static func envelope(from event: Online.Event) -> (DirectEnvelope, mailbox: String)? {
        guard event.kind == Online.kind, event.isValid, let mailbox = event.tags.first(where: { $0.first == "p" })?.last,
              let bytes = Data(base64Encoded: event.content) else { return nil }
        return (DirectEnvelope(bytes: bytes), mailbox)
    }
}
