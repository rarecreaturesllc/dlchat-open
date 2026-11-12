import CryptoKit
import XCTest
@testable import DLCore

private struct Vectors: Decodable {
    struct RoomKeys: Decodable {
        let room, roomKeyHex, macKeyHex, encKeyHex: String
    }
    struct PhraseCase: Decodable {
        let words: Int
        let entropyHex: String
        let indices: [Int]
        let phrase, masterHex, safety: String
        let rooms: [RoomKeys]
    }
    struct FrameCase: Decodable {
        let phrase: Int
        let room: String
        let tagBits, sentSlot, flags, salt: Int
        let bodyBits, tagHex, nonceHex, frameHex: String
        let frameBitCount: Int
    }
    let phrases: [PhraseCase]
    let frames: [FrameCase]
}

private func bytes(hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}

private func hex(_ key: SymmetricKey) -> String {
    key.bytes.map { String(format: "%02x", $0) }.joined()
}

private func bits(from string: String) -> Bits {
    var out = Bits()
    for c in string { out.append(c == "1" ? 1 : 0, width: 1) }
    return out
}

/// One slow key derivation shared by the round-trip tests.
private let sharedPhrase = try! Phrase.generate(words: 10)
private let sharedKeys = Keys(phrase: sharedPhrase)
private let otherKeys = Keys(phrase: try! Phrase.generate(words: 10))
private let sentAt = Frame.epoch.addingTimeInterval(300 * 4242 + 17)

final class FrameTests: XCTestCase {
    func testVectorsMatchIndependentScript() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("vectors.json")
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))

        var keysByPhrase: [Int: [String: Keys]] = [:]
        for (i, p) in vectors.phrases.enumerated() {
            let phrase = try Phrase(entropy: bytes(hex: p.entropyHex), words: p.words)
            XCTAssertEqual(phrase.indices, p.indices)
            XCTAssertEqual(phrase.text, p.phrase)
            XCTAssertEqual(try Phrase.parse(p.phrase), phrase)
            let master = Keys.derivedMaster(phrase: phrase)
            XCTAssertEqual(hex(master), p.masterHex)
            XCTAssertEqual(Keys(master: master).safetyWords.joined(separator: " "), p.safety)
            for r in p.rooms {
                let k = Keys(master: master, room: r.room)
                XCTAssertEqual(hex(k.roomKey), r.roomKeyHex)
                XCTAssertEqual(hex(k.macKey), r.macKeyHex)
                XCTAssertEqual(hex(k.encKey), r.encKeyHex)
            }
            keysByPhrase[i] = [:]
            for room in Set(vectors.frames.filter { $0.phrase == i }.map(\.room)) {
                keysByPhrase[i]![room] = Keys(master: master, room: room)
            }
        }

        for f in vectors.frames {
            let keys = try XCTUnwrap(keysByPhrase[f.phrase]?[f.room])
            let when = Frame.epoch.addingTimeInterval(Double(f.sentSlot) * 300 + 1)
            let frame = try Frame.seal(
                body: bits(from: f.bodyBits), flags: UInt8(f.flags), sentAt: when, keys: keys,
                tagBits: f.tagBits, salt: UInt8(f.salt))
            XCTAssertEqual(frame.bits.count, f.frameBitCount)
            XCTAssertEqual(frame.bits.bytes, bytes(hex: f.frameHex))
            XCTAssertEqual(Array(frame.bits.bytes.prefix(f.tagBits / 8)), bytes(hex: f.tagHex))
            let opened = try XCTUnwrap(Frame.open(frame, tagBits: f.tagBits, trying: [keys]))
            XCTAssertEqual(opened.body, bits(from: f.bodyBits))
            XCTAssertEqual(opened.sentAt, Frame.epoch.addingTimeInterval(Double(f.sentSlot) * 300))
            XCTAssertEqual(Int(opened.flags), f.flags)
            XCTAssertEqual(Int(opened.salt), f.salt)
        }
    }

    func testRoundTripForRandomInput() throws {
        for tagBits in [64, 128] {
            for _ in 0..<200 {
                let length = Int.random(in: 0...400)
                var body = Bits()
                for _ in 0..<length { body.append(UInt64.random(in: 0...1), width: 1) }
                let flags = UInt8.random(in: 0..<4)
                let frame = try Frame.seal(body: body, flags: flags, sentAt: sentAt, keys: sharedKeys, tagBits: tagBits)
                XCTAssertEqual(frame.bits.count, tagBits + 28 + length)
                let opened = try XCTUnwrap(Frame.open(frame, tagBits: tagBits, trying: [otherKeys, sharedKeys]))
                XCTAssertEqual(opened.body, body)
                XCTAssertEqual(opened.flags, flags)
                XCTAssertEqual(opened.keysIndex, 1)
                XCTAssertEqual(opened.sentAt, Frame.epoch.addingTimeInterval(300 * 4242))
            }
        }
    }

    func testAnyFlippedBitFails() throws {
        for tagBits in [64, 128] {
            let body = bits(from: "1011001110001011100101")
            let frame = try Frame.seal(body: body, sentAt: sentAt, keys: sharedKeys, tagBits: tagBits)
            for i in 0..<frame.bits.count {
                var damaged = frame.bits
                damaged.flip(at: i)
                XCTAssertNil(Frame.open(Frame(bits: damaged), tagBits: tagBits, trying: [sharedKeys]), "bit \(i)")
            }
        }
    }

    func testWrongKeysFailAndRoomsIsolate() throws {
        let frame = try Frame.seal(body: bits(from: "110"), sentAt: sentAt, keys: sharedKeys, tagBits: 64)
        XCTAssertNil(Frame.open(frame, tagBits: 64, trying: [otherKeys]))
        let masterOnly = Keys(master: sharedKeys.master, room: "bridge")
        XCTAssertNil(Frame.open(frame, tagBits: 64, trying: [masterOnly]))
        XCTAssertNil(Frame.open(frame, tagBits: 128, trying: [sharedKeys]))
        XCTAssertNotNil(Frame.open(frame, tagBits: 64, trying: [Keys(master: sharedKeys.master, room: "")]))
    }

    func testRejectsBadArguments() {
        XCTAssertThrowsError(try Frame.seal(body: Bits(), sentAt: sentAt, keys: sharedKeys, tagBits: 32))
        XCTAssertThrowsError(try Frame.seal(body: Bits(), flags: 4, sentAt: sentAt, keys: sharedKeys, tagBits: 64))
        XCTAssertNil(Frame.open(Frame(bits: Bits()), tagBits: 64, trying: [sharedKeys]))
    }

    func testOutOfRangeClockClampsInsteadOfThrowing() throws {
        let last = Frame.epoch.addingTimeInterval(300 * Double((1 << 20) - 1))
        let cases: [(Date, Date)] = [
            (Frame.epoch.addingTimeInterval(-1), Frame.epoch),
            (Date(timeIntervalSince1970: 0), Frame.epoch),
            (.distantPast, Frame.epoch),
            (last.addingTimeInterval(300 * 5), last),
            (.distantFuture, last),
        ]
        for (clock, expected) in cases {
            let frame = try Frame.seal(body: bits(from: "101"), sentAt: clock, keys: sharedKeys, tagBits: 64)
            let opened = try XCTUnwrap(Frame.open(frame, tagBits: 64, trying: [sharedKeys]))
            XCTAssertEqual(opened.sentAt, expected)
            XCTAssertEqual(opened.body, bits(from: "101"))
        }
    }

    func testRoomWordIsTrimmedAndNormalized() throws {
        let composed = Keys(master: sharedKeys.master, room: "caf\u{e9}")
        for spelling in [" Cafe\u{301} ", "CAF\u{c9}\n", "cafe\u{301}"] {
            XCTAssertEqual(Keys(master: sharedKeys.master, room: spelling).roomKey.bytes, composed.roomKey.bytes, spelling)
        }
        XCTAssertNotEqual(Keys(master: sharedKeys.master, room: "cafe").roomKey.bytes, composed.roomKey.bytes)
        XCTAssertEqual(Keys(master: sharedKeys.master, room: "  \n").roomKey.bytes, Keys(master: sharedKeys.master).roomKey.bytes)
    }

    func testGeneratedPhrasesParse() throws {
        for count in Phrase.lengths {
            let phrase = try Phrase.generate(words: count)
            XCTAssertEqual(phrase.words.count, count)
            XCTAssertEqual(try Phrase.parse(phrase.text.uppercased()), phrase)
        }
        XCTAssertThrowsError(try Phrase.generate(words: 12))
    }

    func testPhraseParseNamesTheProblem() throws {
        let phrase = try Phrase.generate(words: 10)
        var words = phrase.words
        words[3] = "zzzzqq"
        XCTAssertThrowsError(try Phrase.parse(words.joined(separator: " "))) {
            XCTAssertEqual($0 as? PhraseError, .unknownWord(3))
        }
        XCTAssertThrowsError(try Phrase.parse(phrase.words.dropLast().joined(separator: " "))) {
            XCTAssertEqual($0 as? PhraseError, .unsupportedLength(9))
        }
        // Changing one word changes the checksum unless the 4 check bits happen to agree.
        var rejected = 0
        for index in 0..<64 where index != phrase.indices[0] {
            var changed = phrase.indices
            changed[0] = index
            let text = changed.map(WordList.word(at:)).joined(separator: " ")
            do { _ = try Phrase.parse(text) } catch PhraseError.badChecksum { rejected += 1 }
        }
        XCTAssertGreaterThan(rejected, 40)
    }

    func testBitsBasics() {
        var b = Bits()
        b.append(0b101, width: 3)
        b.append(0xFF, width: 8)
        XCTAssertEqual(b.count, 11)
        XCTAssertEqual(b.value(at: 0, width: 3), 0b101)
        XCTAssertEqual(b.bytes, [0b1011_1111, 0b1110_0000])
        XCTAssertEqual(Bits(bytes: [0xFF], count: 3).bytes, [0xE0])
    }
}
