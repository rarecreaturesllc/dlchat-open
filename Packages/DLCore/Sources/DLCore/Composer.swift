import Foundation

public enum ComposerError: Error, Equatable {
    /// The sealed message is longer than one tone burst can carry.
    case tooLongForSound
}

/// Plain text to the spoken words of a sealed voice message (tag 64 bits), and the word count before sealing.
public enum Composer {
    public static let voiceTagBits = 64

    /// Words that `compose` will produce for `text`. Padding length depends only on the text length,
    /// so this needs no keys. Zero for text with no letters or digits.
    public static func wordCount(text: String, tagBits: Int = voiceTagBits) -> Int {
        guard let body = try? TextCodec.encode(text) else { return 0 }
        let padded = WordCodec.pad(body, tagBits: tagBits)
        return (tagBits + Frame.headerBits + padded.count) / WordList.bitsPerWord
    }

    public static func compose(
        text: String, keys: Keys, sentAt: Date = Date(), flags: UInt8 = 0, tagBits: Int = voiceTagBits
    ) throws -> [String] {
        let body = WordCodec.pad(try TextCodec.encode(text), tagBits: tagBits)
        let frame = try Frame.seal(body: body, flags: flags, sentAt: sentAt, keys: keys, tagBits: tagBits)
        return try WordCodec.encode(frame)
    }

    /// The text for a QR code carrying the sealed message (128-bit tag, see `QRTransport`).
    public static func composeQR(text: String, keys: Keys, sentAt: Date = Date(), flags: UInt8 = 0) throws -> String {
        let tagBits = QRTransport.tagBits
        let body = WordCodec.pad(try TextCodec.encode(text), tagBits: tagBits)
        let frame = try Frame.seal(body: body, flags: flags, sentAt: sentAt, keys: keys, tagBits: tagBits)
        return QRTransport.payload(for: frame)
    }

    /// The audio samples (8 kHz mono) of a sealed message for the tone modem (128-bit tag, as QR).
    public static func composeTone(text: String, keys: Keys, sentAt: Date = Date(), flags: UInt8 = 0) throws -> [Float] {
        Modem.encode(try composeToneFrame(text: text, keys: keys, sentAt: sentAt, flags: flags))
    }

    /// The sealed frame the tones carry (Encrypt Sound posts it in Chat; `Modem.encode` turns it into sound).
    public static func composeToneFrame(text: String, keys: Keys, sentAt: Date = Date(), flags: UInt8 = 0) throws -> Frame {
        let tagBits = QRTransport.tagBits
        let body = WordCodec.pad(try TextCodec.encode(text), tagBits: tagBits)
        let frame = try Frame.seal(body: body, flags: flags, sentAt: sentAt, keys: keys, tagBits: tagBits)
        // `Modem.encode` stops the app on a frame over one burst, so refuse it here.
        guard frame.bits.bytes.count <= Modem.maxPayload else { throw ComposerError.tooLongForSound }
        return frame
    }
}
