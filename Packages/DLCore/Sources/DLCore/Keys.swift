import CommonCrypto
import CryptoKit
import Foundation

/// Every key derived from a phrase and an optional room word (blueprint
/// section 3). The PBKDF2 step is deliberately slow (600,000 rounds): build
/// `Keys` off the main actor, once per phrase, and cache `master`.
public struct Keys {
    static let kdfSalt = Data("DLChat/v1/kdf".utf8)
    static let kdfRounds: UInt32 = 600_000

    let master: SymmetricKey
    let roomKey: SymmetricKey
    let macKey: SymmetricKey
    let encKey: SymmetricKey

    public init(phrase: Phrase, room: String = "") {
        self.init(master: Keys.derivedMaster(phrase: phrase), room: room)
    }

    /// Rebuilds keys from a stored master key (see `masterData`); skips the slow PBKDF2 step.
    public init(masterData: Data, room: String = "") {
        self.init(master: SymmetricKey(data: masterData), room: room)
    }

    /// The derived master key, for the caller's Keychain cache. Treat it like the phrase.
    public var masterData: Data { Data(master.bytes) }

    /// Reuses an already derived master key, so changing rooms stays fast.
    public init(master: SymmetricKey, room: String = "") {
        self.master = master
        roomKey = Keys.hkdf(master, info: "room/" + Keys.normalizedRoom(room))
        macKey = Keys.hkdf(roomKey, info: "mac")
        encKey = Keys.hkdf(roomKey, info: "enc")
    }

    /// Three list words both phones can read aloud to confirm they share a phrase.
    public var safetyWords: [String] {
        let bytes = Keys.hkdf(master, info: "safety").withUnsafeBytes { Array($0.prefix(4)) }
        let value = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return [22, 12, 2].map { WordList.word(at: Int((value >> UInt32($0)) & 1023)) }
    }

    /// Room words are trimmed, put in Unicode NFC and lowercased, so two keyboards give the same key.
    public static func normalizedRoom(_ room: String) -> String {
        room.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
            .precomposedStringWithCanonicalMapping
    }

    static func derivedMaster(phrase: Phrase) -> SymmetricKey {
        let password = Array(phrase.text.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = kdfSalt.withUnsafeBytes { salt in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count,
                salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), kdfRounds, &out, out.count)
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return SymmetricKey(data: out)
    }

    static func hkdf(_ key: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key, salt: Data(), info: Data(info.utf8), outputByteCount: 32)
    }
}

extension SymmetricKey {
    var bytes: [UInt8] { withUnsafeBytes { Array($0) } }
}
