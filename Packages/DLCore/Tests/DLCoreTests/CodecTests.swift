import CryptoKit
import XCTest
@testable import DLCore

final class CodecTests: XCTestCase {
    /// SHA-256 of Resources/dictionary.txt. Changing it splits every group, so
    /// this only changes together with a protocol version bump.
    private static let pinnedDictionarySHA256 = "6d6d83882539b1dfd493b09de4a30b0734eb602267a6568137e81d1250c60907"

    private let keys = Keys(master: SymmetricKey(data: Array(repeating: 7, count: 32)))

    // MARK: Dictionary

    func testDictionaryShape() {
        let words = TextCodec.dictionary
        XCTAssertGreaterThan(words.count, 500)
        XCTAssertEqual(Set(words).count, words.count)
        for word in words {
            XCTAssertNotNil(word.range(of: "^[a-z]+('[a-z]+)?$", options: .regularExpression), word)
        }
        for word in ["water", "bandage", "generator", "ammo", "rifle", "noon", "church"] {
            XCTAssertTrue(words.contains(word), word)
        }
    }

    func testDictionaryHashIsPinned() throws {
        let url = try XCTUnwrap(TextCodec.resourceURL)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, Self.pinnedDictionarySHA256)
    }

    // MARK: TextCodec

    private static let listed = [
        "yes", "need water at north gate", "meet at the church at noon",
        "doctor needed at the smith house now bring bandages",
        "generator is out of fuel can you spare five gallons",
        "zxqv unknownword", "call 911 now", "gate 7 and gate 12", "b52 over mount xyzzy",
        "Need WATER, at north-gate!", "  spaced   out  ",
    ]

    func testListedSentencesRoundTrip() throws {
        for text in Self.listed {
            let bits = try TextCodec.encode(text)
            XCTAssertEqual(try TextCodec.decode(bits), TextCodec.normalize(text), text)
        }
    }

    func testRandomSentencesRoundTrip() throws {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ")
        for i in 0..<10_000 {
            var text = ""
            let pieces = Int.random(in: 1...8, using: &generator)
            for _ in 0..<pieces {
                if Bool.random(using: &generator) {
                    text += TextCodec.dictionary.randomElement(using: &generator)! + " "
                } else {
                    let length = Int.random(in: 1...10, using: &generator)
                    text += String((0..<length).map { _ in alphabet.randomElement(using: &generator)! }) + " "
                }
            }
            guard !TextCodec.normalize(text).isEmpty else { continue }
            let bits = try TextCodec.encode(text)
            XCTAssertEqual(try TextCodec.decode(bits), TextCodec.normalize(text), "case \(i): \(text)")
        }
    }

    func testTrailingPaddingIsIgnored() throws {
        var bits = try TextCodec.encode("need water")
        bits.append(0x2B5, width: 10)
        XCTAssertEqual(try TextCodec.decode(bits), "need water")
    }

    func testEmptyAndTruncated() throws {
        XCTAssertThrowsError(try TextCodec.encode("  !! ")) { XCTAssertEqual($0 as? TextCodecError, .emptyMessage) }
        let bits = try TextCodec.encode("need water at north gate")
        let cut = bits.slice(from: 0, count: bits.count - 3)
        XCTAssertThrowsError(try TextCodec.decode(cut))
    }

    // MARK: WordCodec

    func testFramesRoundTripThroughWords() throws {
        for tagBits in [64, 128] {
            for text in Self.listed {
                let body = WordCodec.pad(try TextCodec.encode(text), tagBits: tagBits)
                let frame = try Frame.seal(body: body, sentAt: Frame.epoch.addingTimeInterval(3600), keys: keys, tagBits: tagBits)
                XCTAssertEqual(frame.bits.count % 10, 0)
                XCTAssertGreaterThanOrEqual(frame.bits.count - tagBits, WordCodec.minimumBodyWords * 10)
                let words = try WordCodec.encode(frame)
                let back = try WordCodec.decode(words.map { $0.uppercased() })
                XCTAssertEqual(back, frame)
                let opened = try XCTUnwrap(Frame.open(back, tagBits: tagBits, trying: [keys]))
                XCTAssertEqual(try TextCodec.decode(opened.body), TextCodec.normalize(text))
            }
        }
    }

    func testUnknownWordNamesPosition() {
        XCTAssertThrowsError(try WordCodec.decode([WordList.words[0], "xyzzy"])) {
            XCTAssertEqual($0 as? WordCodecError, .unknownWord(index: 1))
        }
    }

    // MARK: Length against the blueprint

    /// Words said with the 64-bit tag, measured. `estimate` is the blueprint's
    /// figure. The dictionary here is hand-built and smaller than the planned
    /// ~4096 entries, so common sentences come out shorter than estimated.
    private static let samples: [(text: String, estimate: Int?, measured: Int)] = [
        ("yes", 11, 11), ("need water at north gate", 16, 15), ("meet at the church at noon", 18, 15),
        ("doctor needed at the smith house now bring bandages", 24, 25),
        ("generator is out of fuel can you spare five gallons", 30, 19),
        ("all clear", nil, 12), ("fuel low at the farm", nil, 15), ("rifle shots near the bridge", nil, 15),
        ("send medic to the school now", nil, 15), ("roger copy that moving out", nil, 15),
    ]

    /// Everyday texts the owner tried on 2026-11-07, before and after the casual words: 34 -> 24 and 76 -> 38.
    private static let casual: [(text: String, measured: Int)] = [
        ("hey guys im going outside and gonna go get food. \n\ndo you need anything else?", 24),
        ("hey guys, I’m gonna go outside and take a walk. I wanted to see if anybody was interested in going with me or maybe we could hang out together and get breakfast.", 38),
    ]

    func testCasualLengths() {
        for sample in Self.casual {
            XCTAssertEqual(Composer.wordCount(text: sample.text), sample.measured, sample.text)
        }
    }

    func testContractionsStayWholeAndRoundTrip() throws {
        // Straight and curly apostrophes give the same dictionary word.
        XCTAssertEqual(TextCodec.normalize("I’m here, I'm HERE"), "i'm here i'm here")
        XCTAssertEqual(try TextCodec.encode("i'm"), try TextCodec.encode("I’m"))
        // A contraction that is not a dictionary word splits as it did before; stray apostrophes are separators.
        for (text, expected) in [("y’know", "y know"), ("'quoted' dogs'", "quoted dogs"), ("it''s", "it s"), ("12'5", "12 5")] {
            XCTAssertEqual(TextCodec.normalize(text), expected, text)
            XCTAssertEqual(try TextCodec.decode(try TextCodec.encode(text)), expected, text)
        }
        XCTAssertEqual(TextCodec.spelledWords(in: "hey I’m gonna see zorbly and zorbly"), ["zorbly"])
    }

    func testSampleLengths() throws {
        for sample in Self.samples {
            let body = WordCodec.pad(try TextCodec.encode(sample.text), tagBits: 64)
            let frame = try Frame.seal(body: body, sentAt: Frame.epoch, keys: keys, tagBits: 64)
            XCTAssertEqual(frame.bits.count / 10, sample.measured, sample.text)
            if let estimate = sample.estimate {
                // Never more than 10% longer than the blueprint said.
                XCTAssertLessThanOrEqual(Double(sample.measured), Double(estimate) * 1.10, sample.text)
            }
        }
    }
}
