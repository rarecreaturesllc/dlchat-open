import CryptoKit
import Foundation

/// Internet Messages (one-to-one chats with anyone who has DLChat, no group phrase): the primitives.
/// Design: docs/design/internet-messages.md.
///
/// Post-quantum key agreement is ML-KEM-768 from CryptoKit, which ships with iOS 26 and macOS 26.
/// Older systems cannot make or open Internet Messages at all (`DirectError.needsNewerSystem`), rather
/// than silently falling back to classical-only keys.
public enum DirectError: Error, Equatable {
    case needsNewerSystem
    case malformed
    case notForUs
    case tooLarge
    case noSendingChain
    case tooManySkipped
    case unknownKEMKey
    case expiredInvite
}

enum PQ {
    static let publicKeySize = 1184
    static let ciphertextSize = 1088

    /// A new ML-KEM-768 key: (private seed to store, public key to share).
    static func generate() throws -> (seed: Data, publicKey: Data) {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw DirectError.needsNewerSystem }
        let key = try MLKEM768.PrivateKey()
        return (key.seedRepresentation, key.publicKey.rawRepresentation)
    }

    /// Encapsulates a fresh secret to `publicKey`: (shared secret, ciphertext to send).
    static func encapsulate(to publicKey: Data) throws -> (secret: Data, ciphertext: Data) {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw DirectError.needsNewerSystem }
        let key = try MLKEM768.PublicKey(rawRepresentation: publicKey)
        let result = try key.encapsulate()
        return (result.sharedSecret.withUnsafeBytes { Data($0) }, result.encapsulated)
    }

    static func decapsulate(seed: Data, ciphertext: Data) throws -> Data {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw DirectError.needsNewerSystem }
        let key = try MLKEM768.PrivateKey(seedRepresentation: seed, publicKey: nil)
        return try key.decapsulate(ciphertext).withUnsafeBytes { Data($0) }
    }

    /// Four bytes naming a KEM public key, so the receiver knows which private key to use.
    static func keyID(_ publicKey: Data) -> Data { Data(SHA256.hash(data: publicKey).prefix(4)) }
}

enum DirectKDF {
    static func hkdf(_ ikm: Data, salt: Data = Data(), info: String, count: Int = 32) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: Data(info.utf8),
                               outputByteCount: count).withUnsafeBytes { Data($0) }
    }

    /// Root chain step: (new root key, new chain key).
    static func root(_ rootKey: Data, _ input: Data) -> (Data, Data) {
        let out = hkdf(input, salt: rootKey, info: "DLChat/direct/v1/root", count: 64)
        return (out.prefix(32), out.suffix(32))
    }

    /// Symmetric chain step: (message key, next chain key).
    static func chain(_ chainKey: Data) -> (Data, Data) {
        let key = SymmetricKey(data: chainKey)
        let message = Data(HMAC<SHA256>.authenticationCode(for: Data([1]), using: key))
        let next = Data(HMAC<SHA256>.authenticationCode(for: Data([2]), using: key))
        return (message, next)
    }

    static func dh(_ privateKey: Data, _ publicKey: Data) throws -> Data {
        let mine = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let theirs = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let secret = try mine.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
        // A handful of public keys (the low-order points) give an all-zero secret whatever our key is.
        // Refuse them here rather than lean on the other inputs to the key derivation.
        guard secret.contains(where: { $0 != 0 }) else { throw DirectError.malformed }
        return secret
    }

    static func newX25519() -> (privateKey: Data, publicKey: Data) {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return (key.rawRepresentation, key.publicKey.rawRepresentation)
    }
}

/// Little helpers for the binary formats.
struct ByteWriter {
    private(set) var data = Data()
    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: Int) { data.append(UInt8((v >> 8) & 0xFF)); data.append(UInt8(v & 0xFF)) }
    mutating func u32(_ v: UInt32) { for shift in [24, 16, 8, 0] { data.append(UInt8((v >> UInt32(shift)) & 0xFF)) } }
    mutating func bytes(_ d: Data) { data.append(d) }
    /// A length-prefixed (two-byte) field.
    mutating func field(_ d: Data) { u16(d.count); data.append(d) }
}

struct ByteReader {
    private let data: [UInt8]
    private(set) var offset = 0
    init(_ data: Data) { self.data = [UInt8](data) }
    var remaining: Int { data.count - offset }
    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw DirectError.malformed }
        defer { offset += 1 }
        return data[offset]
    }
    mutating func u16() throws -> Int { Int(try u8()) << 8 | Int(try u8()) }
    mutating func u32() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 { v = v << 8 | UInt32(try u8()) }
        return v
    }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw DirectError.malformed }
        defer { offset += count }
        return Data(data[offset..<(offset + count)])
    }
    mutating func field() throws -> Data { try bytes(try u16()) }
    mutating func rest() -> Data { defer { offset = data.count }; return Data(data[offset...]) }
}

extension Data {
    /// URL-safe base64 without padding, for invite links.
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL text: String) {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
