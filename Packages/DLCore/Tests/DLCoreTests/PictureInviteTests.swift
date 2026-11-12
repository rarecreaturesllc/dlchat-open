import CoreGraphics
import ImageIO
import XCTest
@testable import DLCore

final class PictureInviteTests: XCTestCase {
    private let password = "maple river stone owl"

    /// Re-encodes like Messages might: JPEG at `quality`, scaled by `scale`.
    private func recompress(_ image: CGImage, quality: Double, scale: Double) throws -> CGImage {
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(out, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testRoundTripThroughThePicture() throws {
        let phrase = try Phrase.generate(words: 15)
        let image = try PictureInvite.render(phrase: phrase, name: "Maple Street", password: password)
        XCTAssertEqual(image.width, 1200)
        let payload = try XCTUnwrap(PictureInvite.read(image))
        let opened = try PictureInvite.unlock(payload, password: "  Maple RIVER stone   owl ")
        XCTAssertEqual(opened.phrase, phrase)
        XCTAssertEqual(opened.name, "Maple Street")
        XCTAssertThrowsError(try PictureInvite.unlock(payload, password: "maple river stone cat")) {
            XCTAssertEqual($0 as? PictureInvite.UnlockError, .wrongPassword)
        }
    }

    func testSurvivesMessagesStyleRecompressionAndADamagedCorner() throws {
        let phrase = try Phrase.generate(words: 20)
        let image = try PictureInvite.render(phrase: phrase, name: "", password: password)
        for (quality, scale) in [(0.3, 0.5), (0.5, 0.75), (0.7, 1.0)] {
            let copy = try recompress(image, quality: quality, scale: scale)
            let payload = try XCTUnwrap(PictureInvite.read(copy), "quality \(quality), scale \(scale)")
            XCTAssertEqual(try PictureInvite.unlock(payload, password: password).phrase, phrase)
        }
        // Scribble over a patch of the starfield (top right): Reed-Solomon repairs it.
        let w = image.width, h = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: w - 200, y: h - 100, width: 200, height: 100))  // top-right, CG origin is bottom-left
        let payload = try XCTUnwrap(PictureInvite.read(try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(try PictureInvite.unlock(payload, password: password).phrase, phrase)
    }

    /// Reed-Solomon repairs 32 bad bytes. After Messages-style recompression the stars alone must read
    /// with at most half that, so faint stars never eat the margin a damaged patch needs.
    func testStarsReadWithMarginAfterRecompression() throws {
        for words in [10, 20] {
            let image = try PictureInvite.render(phrase: try Phrase.generate(words: words), name: "Porch", password: password)
            let clean = try XCTUnwrap(PictureInvite.read(image))
            let expected = ReedSolomon.encode(clean, parity: PictureInvite.parity)
            XCTAssertEqual(PictureInvite.rawCodeword(image), expected, "a fresh picture reads without repair")
            for (quality, scale) in [(0.3, 0.5), (0.2, 0.5), (0.5, 0.75)] {
                let seen = try XCTUnwrap(PictureInvite.rawCodeword(try recompress(image, quality: quality, scale: scale)))
                let bad = zip(seen, expected).filter { $0 != $1 }.count
                print("margin: \(words) words, quality \(quality), scale \(scale): \(bad) bad bytes")
                XCTAssertLessThanOrEqual(bad, quality < 0.3 ? 24 : 16, "quality \(quality), scale \(scale)")
            }
        }
    }

    func testOtherPicturesAreNotInvites() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 1500, bitsPerComponent: 8, bytesPerRow: 4800,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1500))
        XCTAssertNil(PictureInvite.read(try XCTUnwrap(context.makeImage())))
        // A crop (a screenshot) changes the shape and is refused rather than misread.
        let invite = try PictureInvite.render(phrase: try Phrase.generate(words: 10), name: "", password: password)
        XCTAssertNil(PictureInvite.read(try XCTUnwrap(invite.cropping(to: CGRect(x: 0, y: 0, width: 1200, height: 1300)))))
    }

    func testSameGroupSameSceneOtherGroupOtherScene() throws {
        let a = try Phrase.generate(words: 15), b = try Phrase.generate(words: 15)
        XCTAssertEqual(PictureInvite.sceneSeed(a), PictureInvite.sceneSeed(a))
        XCTAssertNotEqual(PictureInvite.sceneSeed(a), PictureInvite.sceneSeed(b))
        // Below the starfield: the stars change with every invite, the landscape only with the group.
        func centre(_ image: CGImage) -> Data { PictureInvite.pngData(image.cropping(to: CGRect(x: 0, y: 640, width: 1200, height: 860))!) }
        let first = try PictureInvite.render(phrase: a, name: "", password: password)
        let again = try PictureInvite.render(phrase: a, name: "", password: "other words here now")
        XCTAssertEqual(centre(first), centre(again), "the painting depends only on the group")
        XCTAssertNotEqual(centre(first), centre(try PictureInvite.render(phrase: b, name: "", password: password)))
        // Samples for eyeballing, when asked for.
        if let dir = ProcessInfo.processInfo.environment["DLCHAT_PICTURE_SAMPLES"] {
            for n in 0..<6 {
                let image = try PictureInvite.render(phrase: try Phrase.generate(words: 15), name: "", password: password)
                try PictureInvite.pngData(image).write(to: URL(fileURLWithPath: dir).appendingPathComponent("sample-\(n).png"))
            }
        }
    }

    func testPasswordIsListWordsOfTheChosenLength() throws {
        for count in PictureInvite.passwordWordCounts {
            let words = PictureInvite.makePassword(words: count)
            XCTAssertEqual(words.count, count)
            XCTAssertTrue(words.allSatisfy(WordList.words.contains))
        }
        XCTAssertNotEqual(PictureInvite.makePassword(), PictureInvite.makePassword())
        // A six-word picture opens with its six words, not with the first four.
        let phrase = try Phrase.generate(words: 10)
        let six = "maple river stone owl badge foam"
        let payload = try XCTUnwrap(PictureInvite.read(try PictureInvite.render(phrase: phrase, name: "Porch", password: six)))
        XCTAssertEqual(try PictureInvite.unlock(payload, password: six).name, "Porch")
        XCTAssertThrowsError(try PictureInvite.unlock(payload, password: password))
    }

    func testPayloadIsSmallAndNamesAreCapped() throws {
        XCTAssertEqual(PictureInvite.payloadSize, 68)
        XCTAssertEqual(PictureInvite.codewordBytes * 8, 1056)
        let phrase = try Phrase.generate(words: 20)
        let payload = try XCTUnwrap(PictureInvite.read(try PictureInvite.render(phrase: phrase, name: "Grandma's lake house crew", password: password)))
        let opened = try PictureInvite.unlock(payload, password: password)
        XCTAssertEqual(opened.phrase, phrase)
        XCTAssertEqual(opened.name, "Grandma's lake h")
    }
}
