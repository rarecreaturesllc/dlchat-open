import CryptoKit
import Foundation

/// The Double Ratchet (Signal's design) with a post-quantum step mixed into every DH ratchet:
/// each time a side starts a new sending chain it also encapsulates a fresh ML-KEM-768 secret to the
/// other side's newest KEM key, and both feed it into the root chain next to the X25519 output.
/// So a recorded conversation stays sealed even against a future quantum computer that can break
/// X25519, old messages stay safe if a phone is taken later (forward secrecy), and a stolen state
/// heals once both sides have sent again (post-compromise recovery).
///
/// Every message carries the sender's newest KEM public key and the ciphertext of its chain, so a
/// lost first message does not stall the chain (about 2.3 KB per message; relays pad to buckets anyway).
public struct DirectRatchet: Codable, Equatable, Sendable {
    struct KEMKey: Codable, Equatable, Sendable { let id: Data; let seed: Data; let publicKey: Data }

    var rootKey: Data
    var sendPrivate: Data
    var sendPublic: Data
    var theirRatchet: Data?
    var sendChain: Data?
    var receiveChain: Data?
    var sent: UInt32 = 0
    var received: UInt32 = 0
    var previousChainLength: UInt32 = 0
    /// The KEM ciphertext (and the id of the key it was made for) behind the current sending chain.
    var chainCiphertext: Data?
    var chainCiphertextKeyID: Data?
    /// Our KEM keys, newest last; the newest is the one advertised. A few older ones are kept for
    /// messages that crossed in flight.
    var kemKeys: [KEMKey]
    var theirKEM: Data?
    /// Message keys for messages not yet arrived (out of order), by "ratchet key hex/number".
    var skipped: [String: Data] = [:]
    var skippedOrder: [String] = []

    static let maxSkip: UInt32 = 1000
    static let maxStoredSkipped = 2000
    static let keptKEMKeys = 4

    // MARK: Start

    /// The side that scanned the invite (sends first): knows the inviter's ratchet key and KEM key.
    static func initiator(sharedSecret: Data, theirRatchet: Data, theirKEM: Data) throws -> DirectRatchet {
        let kem = try PQ.generate()
        let mine = DirectKDF.newX25519()
        let encapsulated = try PQ.encapsulate(to: theirKEM)
        let dh = try DirectKDF.dh(mine.privateKey, theirRatchet)
        let (root, chain) = DirectKDF.root(sharedSecret, dh + encapsulated.secret)
        return DirectRatchet(rootKey: root, sendPrivate: mine.privateKey, sendPublic: mine.publicKey, theirRatchet: theirRatchet,
                             sendChain: chain, receiveChain: nil, chainCiphertext: encapsulated.ciphertext,
                             chainCiphertextKeyID: PQ.keyID(theirKEM),
                             kemKeys: [KEMKey(id: PQ.keyID(kem.publicKey), seed: kem.seed, publicKey: kem.publicKey)],
                             theirKEM: theirKEM)
    }

    /// The inviter: its invite keys are the first ratchet key pair and the first KEM key.
    static func responder(sharedSecret: Data, ratchetPrivate: Data, ratchetPublic: Data,
                          kemSeed: Data, kemPublic: Data) -> DirectRatchet {
        DirectRatchet(rootKey: sharedSecret, sendPrivate: ratchetPrivate, sendPublic: ratchetPublic, theirRatchet: nil,
                      sendChain: nil, receiveChain: nil, chainCiphertext: nil, chainCiphertextKeyID: nil,
                      kemKeys: [KEMKey(id: PQ.keyID(kemPublic), seed: kemSeed, publicKey: kemPublic)], theirKEM: nil)
    }

    // MARK: Header

    struct Header: Equatable {
        var ratchet: Data          // 32
        var previous: UInt32
        var number: UInt32
        var kemPublic: Data?       // 1184
        var kemKeyID: Data?        // 4
        var kemCiphertext: Data?   // 1088

        var encoded: Data {
            var w = ByteWriter()
            w.bytes(ratchet)
            w.u32(previous)
            w.u32(number)
            w.u8((kemPublic == nil ? 0 : 1) | (kemCiphertext == nil ? 0 : 2))
            if let kemPublic { w.bytes(kemPublic) }
            if let kemCiphertext, let kemKeyID { w.bytes(kemKeyID); w.bytes(kemCiphertext) }
            return w.data
        }

        static func decode(_ r: inout ByteReader) throws -> Header {
            let ratchet = try r.bytes(32)
            let previous = try r.u32(), number = try r.u32()
            let flags = try r.u8()
            guard flags & ~3 == 0 else { throw DirectError.malformed }
            var kemPublic: Data?
            if flags & 1 != 0 { kemPublic = try r.bytes(PQ.publicKeySize) }
            var id: Data?, ct: Data?
            if flags & 2 != 0 { id = try r.bytes(4); ct = try r.bytes(PQ.ciphertextSize) }
            return Header(ratchet: ratchet, previous: previous, number: number, kemPublic: kemPublic, kemKeyID: id, kemCiphertext: ct)
        }
    }

    // MARK: Encrypt

    /// Seals `plaintext` as the next message; returns header + ciphertext.
    mutating func encrypt(_ plaintext: Data) throws -> Data {
        guard let chain = sendChain else { throw DirectError.noSendingChain }
        let (messageKey, next) = DirectKDF.chain(chain)
        let header = Header(ratchet: sendPublic, previous: previousChainLength, number: sent,
                            kemPublic: kemKeys.last?.publicKey, kemKeyID: chainCiphertextKeyID, kemCiphertext: chainCiphertext)
        let encodedHeader = header.encoded
        let sealed = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: messageKey), authenticating: encodedHeader)
        sendChain = next
        sent += 1
        return encodedHeader + sealed.combined
    }

    // MARK: Decrypt

    /// Opens a message. The state changes only if it opens, so a forged or broken message costs nothing.
    mutating func decrypt(_ message: Data) throws -> Data {
        var reader = ByteReader(message)
        let header = try Header.decode(&reader)
        let headerBytes = Data(message.prefix(reader.offset))
        let body = reader.rest()
        var next = self
        let plain = try next.open(header: header, headerBytes: headerBytes, body: body)
        self = next
        return plain
    }

    private mutating func open(header: Header, headerBytes: Data, body: Data) throws -> Data {
        let slot = Self.slot(header.ratchet, header.number)
        if let key = skipped[slot] {
            skipped[slot] = nil
            skippedOrder.removeAll { $0 == slot }
            return try Self.open(body, key: key, header: headerBytes)
        }
        if header.ratchet != theirRatchet {
            try skip(until: header.previous)
            try ratchetStep(header)
        }
        try skip(until: header.number)
        guard let chain = receiveChain else { throw DirectError.malformed }
        let (messageKey, next) = DirectKDF.chain(chain)
        receiveChain = next
        received += 1
        if let kem = header.kemPublic { theirKEM = kem }
        return try Self.open(body, key: messageKey, header: headerBytes)
    }

    private static func open(_ body: Data, key: Data, header: Data) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: body)
        return try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: header)
    }

    private static func slot(_ ratchet: Data, _ number: UInt32) -> String {
        ratchet.map { String(format: "%02x", $0) }.joined() + "/\(number)"
    }

    private mutating func skip(until number: UInt32) throws {
        guard let chain = receiveChain, let ratchet = theirRatchet else { return }
        guard number >= received else { return }
        guard number - received <= Self.maxSkip else { throw DirectError.tooManySkipped }
        var current = chain
        while received < number {
            let (messageKey, next) = DirectKDF.chain(current)
            let slot = Self.slot(ratchet, received)
            skipped[slot] = messageKey
            skippedOrder.append(slot)
            current = next
            received += 1
        }
        receiveChain = current
        while skippedOrder.count > Self.maxStoredSkipped { skipped[skippedOrder.removeFirst()] = nil }
    }

    /// A new ratchet key from the other side: close our receiving chain, open theirs, start our next
    /// sending chain with a fresh X25519 key and a fresh KEM encapsulation.
    private mutating func ratchetStep(_ header: Header) throws {
        // Their KEM ciphertext (if any) was made to one of our KEM keys.
        var theirSecret = Data()
        if let ct = header.kemCiphertext, let id = header.kemKeyID {
            guard let key = kemKeys.first(where: { $0.id == id }) else { throw DirectError.unknownKEMKey }
            theirSecret = try PQ.decapsulate(seed: key.seed, ciphertext: ct)
        }
        previousChainLength = sent
        sent = 0
        received = 0
        theirRatchet = header.ratchet
        if let kem = header.kemPublic { theirKEM = kem }
        let (root1, receive) = DirectKDF.root(rootKey, try DirectKDF.dh(sendPrivate, header.ratchet) + theirSecret)
        receiveChain = receive
        let mine = DirectKDF.newX25519()
        sendPrivate = mine.privateKey
        sendPublic = mine.publicKey
        var ourSecret = Data()
        if let theirKEM {
            let encapsulated = try PQ.encapsulate(to: theirKEM)
            ourSecret = encapsulated.secret
            chainCiphertext = encapsulated.ciphertext
            chainCiphertextKeyID = PQ.keyID(theirKEM)
        } else {
            chainCiphertext = nil
            chainCiphertextKeyID = nil
        }
        let (root2, send) = DirectKDF.root(root1, try DirectKDF.dh(sendPrivate, header.ratchet) + ourSecret)
        rootKey = root2
        sendChain = send
        // A new KEM key for the other side's next chain; keep a few older ones for crossed messages.
        let kem = try PQ.generate()
        kemKeys.append(KEMKey(id: PQ.keyID(kem.publicKey), seed: kem.seed, publicKey: kem.publicKey))
        if kemKeys.count > Self.keptKEMKeys { kemKeys.removeFirst(kemKeys.count - Self.keptKEMKeys) }
    }
}
