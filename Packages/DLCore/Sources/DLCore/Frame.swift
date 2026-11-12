import CryptoKit
import Foundation

public enum FrameError: Error, Equatable {
    case unsupportedTagBits(Int)
    case badField
}

/// What a successfully opened frame held. `body` is the text bits plus any
/// padding; TextCodec (T004) turns it into words.
public struct Opened: Equatable {
    public let sentAt: Date
    public let flags: UInt8
    public let salt: UInt8
    public let body: Bits
    /// Position in the `trying` list of the keys that opened it.
    public let keysIndex: Int
}

/// A sealed message: `tag || (P xor stream)` with no version or marker in the
/// clear (blueprint section 3, SIV construction).
///
/// P = send slot (20 bits) | flags (2) | salt (6) | body bits. The length of P
/// is not sent: the receiver knows the frame length, and it is covered by the tag.
public struct Frame: Equatable {
    public static let epoch = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01 UTC
    public static let slotSeconds: TimeInterval = 300
    static let headerBits = 28

    public let bits: Bits

    public init(bits: Bits) {
        self.bits = bits
    }

    public static func seal(
        body: Bits, flags: UInt8 = 0, sentAt: Date, keys: Keys, tagBits: Int,
        salt: UInt8? = nil
    ) throws -> Frame {
        guard tagBits == 64 || tagBits == 128 else { throw FrameError.unsupportedTagBits(tagBits) }
        guard flags < 4, salt.map({ $0 < 64 }) ?? true else { throw FrameError.badField }
        // Time is display-only, so a wrong clock clamps to the first or last slot instead of failing.
        let rawSlot = (sentAt.timeIntervalSince(epoch) / slotSeconds).rounded(.down)
        let slot = rawSlot.isNaN ? 0 : Int(min(max(rawSlot, 0), Double((1 << 20) - 1)))

        var plain = Bits()
        plain.append(UInt64(slot), width: 20)
        plain.append(UInt64(flags), width: 2)
        plain.append(UInt64(salt ?? UInt8.random(in: 0..<64)), width: 6)
        plain.append(body)

        let tag = makeTag(plain, macKey: keys.macKey, tagBytes: tagBits / 8)
        let cipher = crypt(plain, tag: tag, encKey: keys.encKey)
        var out = Bits(bytes: tag, count: tagBits)
        out.append(cipher)
        return Frame(bits: out)
    }

    /// Tries each key set in order; nil if none authenticates. The reason is
    /// never reported beyond "could not decrypt".
    public static func open(_ frame: Frame, tagBits: Int, trying all: [Keys]) -> Opened? {
        guard tagBits == 64 || tagBits == 128, frame.bits.count >= tagBits + headerBits else { return nil }
        let tagBytes = tagBits / 8
        let tag = Array(frame.bits.bytes.prefix(tagBytes))
        let cipher = frame.bits.slice(from: tagBits, count: frame.bits.count - tagBits)
        for (index, keys) in all.enumerated() {
            let plain = crypt(cipher, tag: tag, encKey: keys.encKey)
            let expected = makeTag(plain, macKey: keys.macKey, tagBytes: tagBytes)
            guard constantTimeEqual(expected, tag) else { continue }
            let slot = Double(plain.value(at: 0, width: 20))
            return Opened(
                sentAt: epoch.addingTimeInterval(slot * slotSeconds),
                flags: UInt8(plain.value(at: 20, width: 2)),
                salt: UInt8(plain.value(at: 22, width: 6)),
                body: plain.slice(from: headerBits, count: plain.count - headerBits),
                keysIndex: index)
        }
        return nil
    }

    /// HMAC-SHA256(macKey, len(P) in bits as 4 bytes big endian || P), truncated.
    private static func makeTag(_ plain: Bits, macKey: SymmetricKey, tagBytes: Int) -> [UInt8] {
        var message = withUnsafeBytes(of: UInt32(plain.count).bigEndian) { Array($0) }
        message += plain.bytes
        return Array(HMAC<SHA256>.authenticationCode(for: message, using: macKey).prefix(tagBytes))
    }

    /// XOR with the ChaCha20 keystream at counter 1 (counter 0 is the Poly1305
    /// key block in ChaChaPoly, whose own tag is discarded). Its own inverse.
    private static func crypt(_ input: Bits, tag: [UInt8], encKey: SymmetricKey) -> Bits {
        let nonceBytes = Array(
            HMAC<SHA256>.authenticationCode(for: Data("nonce".utf8) + tag, using: encKey).prefix(12))
        let stream: [UInt8]
        do {
            let nonce = try ChaChaPoly.Nonce(data: nonceBytes)
            let sealed = try ChaChaPoly.seal(
                Data(count: input.bytes.count), using: encKey, nonce: nonce)
            stream = Array(sealed.ciphertext)
        } catch {
            preconditionFailure("ChaChaPoly rejected a 32-byte key and 12-byte nonce")
        }
        return Bits(bytes: zip(input.bytes, stream).map { $0 ^ $1 }, count: input.count)
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
