import Foundation

/// A sealed frame as the text inside a QR code: base64url of the frame bytes, no marker, so it looks
/// like random data like every other transport. QR frames use the 128-bit tag.
///
/// A frame is a whole number of 10-bit words, so the bit count is recovered from the byte count:
/// two multiples of 10 are never within the same 8 bits.
public enum QRTransport {
    public static let tagBits = 128

    public static func payload(for frame: Frame) -> String {
        Data(frame.bits.bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The frame a scanned string carries, or nil when it is not one (another kind of QR code, a
    /// phrase, or damaged text).
    public static func frame(from payload: String) -> Frame? {
        var text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII }) else { return nil }
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text) else { return nil }
        let bytes = [UInt8](data)
        let bits = (bytes.count * 8 / WordList.bitsPerWord) * WordList.bitsPerWord
        guard bits > 0, (bits + 7) / 8 == bytes.count, bits >= tagBits + Frame.headerBits else { return nil }
        // Spare bits in the last byte must be zero, so no two texts carry the same frame.
        let spare = bytes.count * 8 - bits
        guard spare == 0 || bytes[bytes.count - 1] & UInt8((1 << spare) - 1) == 0 else { return nil }
        return Frame(bits: Bits(bytes: bytes, count: bits))
    }
}
