import XCTest
@testable import DLCore

final class PunctuationTests: XCTestCase {
    private let keys = Keys(phrase: try! Phrase.generate(words: 10))

    private func chat(_ text: String) throws -> String {
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys), ttl: 0)
        return try XCTUnwrap(Receiver.readNearby(wire: wire, trying: [keys])).text
    }

    func testChatKeepsQuestionAndExclamationMarks() throws {
        XCTAssertEqual(try chat("Are you ok? Yes!"), "are you ok? yes!")
        XCTAssertEqual(try chat("what?!"), "what?!")
        XCTAssertEqual(try chat("hello, world. see you at 5!"), "hello, world. see you at 5!")
        XCTAssertEqual(try chat("wow!!!"), "wow!!!")
    }

    func testMarksFollowTheWordsTheCodecMakes() throws {
        // A known contraction is one word, an unknown one two, and letters meeting digits split.
        XCTAssertEqual(try chat("I'm here!"), "i'm here!")
        XCTAssertEqual(try chat("zorp'q ok?"), "zorp q ok?")
        XCTAssertEqual(try chat("room b12?"), "room b 12?")
        XCTAssertEqual(try chat("hi , there"), "hi, there")
    }

    func testMarksInsideWordsOrBeforeAnyWordAreDroppedAsBefore() throws {
        XCTAssertEqual(try chat("pi is 3.5"), "pi is 3 5")
        XCTAssertEqual(try chat("!!hi"), "hi")
        XCTAssertEqual(Punctuation.marks(in: "a-b ; c"), [])
    }

    func testTextWithoutMarksCodesExactlyAsBefore() throws {
        for text in ["meet at the bridge", "i'm 42 today", "dlwords"] {
            XCTAssertEqual(try Punctuation.encode(text), try TextCodec.encode(text))
        }
    }

    func testOlderReadersSeeTheWordsOnly() throws {
        let body = try Punctuation.encode("Are you ok? Yes!")
        XCTAssertEqual(try TextCodec.decode(body), "are you ok yes")
    }

    func testRandomPaddingIsNotReadAsMarks() throws {
        var generator = SystemRandomNumberGenerator()
        let coded = try TextCodec.encode("meet at the bridge")
        for _ in 0..<2000 {
            var body = coded
            for _ in 0..<3 { body.append(UInt64.random(in: 0..<(1 << 32), using: &generator), width: 32) }
            XCTAssertEqual(Punctuation.read(body, from: coded.count, wordCount: 4), [])
        }
    }

    func testDamagedOrMisplacedTrailerIsIgnored() throws {
        let coded = try TextCodec.encode("are you ok yes")
        let trailer = Punctuation.trailer(Punctuation.marks(in: "are you ok? yes!"))
        var body = coded
        body.append(trailer)
        XCTAssertEqual(Punctuation.read(body, from: coded.count, wordCount: 4).count, 2)
        // A mark after a word the text does not have.
        XCTAssertEqual(Punctuation.read(body, from: coded.count, wordCount: 3), [])
        for bit in coded.count..<body.count {
            var damaged = body
            damaged.flip(at: bit)
            XCTAssertEqual(Punctuation.read(damaged, from: coded.count, wordCount: 4), [], "bit \(bit)")
        }
    }
}
