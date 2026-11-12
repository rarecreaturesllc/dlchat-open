import CoreGraphics
import CoreText
import ImageIO
import XCTest
@testable import DLCore

/// Screenshots of a picture invite: the picture smaller than made, framed by a screen.
final class PictureInviteScreenshotTests: XCTestCase {
    private let password = "maple river stone owl"

    /// A phone screenshot: `screen` pixels, background `gray`, the picture `margin` px from each side,
    /// `top` px down, corners rounded, a title above and lines of text below.
    private func screenshot(of picture: CGImage, screen: (Int, Int), margin: Int, top: Int, background: CGFloat) throws -> CGImage {
        let (w, h) = screen
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: background, green: background * 1.1, blue: background * 1.25, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let pw = Double(w - 2 * margin), ph = pw * 1.25
        let rect = CGRect(x: Double(margin), y: Double(h - top) - ph, width: pw, height: ph)  // CG is bottom-up
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil))
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(picture, in: rect)
        ctx.restoreGState()
        let text = background > 0.5 ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
        func line(_ s: String, y: Double, size: Double) {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                  NSAttributedString.Key(kCTForegroundColorAttributeName as String): text])
            ctx.textPosition = CGPoint(x: Double(margin), y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        line("Picture invite                Close", y: Double(h - top) + 40, size: 60)
        for (i, word) in ["Password: read it to your friend", "maple    river", "stone    owl"].enumerated() {
            line(word, y: rect.minY - 90 - Double(i) * 110, size: 54)
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    func testOpensFromScreenshotsAtPhoneSizes() throws {
        let phrase = try Phrase.generate(words: 15)
        let picture = try PictureInvite.render(phrase: phrase, name: "Porch", password: password)
        let cases: [(name: String, screen: (Int, Int), margin: Int, top: Int, bg: CGFloat)] = [
            ("DLChat screen, iPhone Pro", (1206, 2622), 72, 330, 0.06),
            ("DLChat screen, iPhone Pro Max", (1320, 2868), 72, 340, 0.06),
            ("DLChat screen, iPhone SE", (750, 1334), 48, 160, 0.06),
            ("Photos, black", (1206, 2622), 0, 560, 0),
            ("Photos, white", (1206, 2622), 0, 560, 1),
            ("Messages bubble", (1206, 2622), 220, 700, 1),
        ]
        for c in cases {
            let shot = try screenshot(of: picture, screen: c.screen, margin: c.margin, top: c.top, background: c.bg)
            let start = Date()
            let payload = PictureInvite.read(shot)
            print("SHOT \(c.name): scale \(String(format: "%.2f", Double(c.screen.0 - 2 * c.margin) / 1200)), \(payload != nil ? "opened" : "FAILED"), \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            let opened = try PictureInvite.unlock(try XCTUnwrap(payload, c.name), password: password)
            XCTAssertEqual(opened.phrase, phrase, c.name)
        }
    }

    /// A screenshot sent on through Messages: JPEG, sometimes smaller.
    func testOpensAScreenshotRecompressedAsJPEG() throws {
        let phrase = try Phrase.generate(words: 10)
        let picture = try PictureInvite.render(phrase: phrase, name: "", password: password)
        let shot = try screenshot(of: picture, screen: (1206, 2622), margin: 72, top: 330, background: 0.06)
        for (quality, scale) in [(0.8, 1.0), (0.6, 1.0), (0.6, 0.75)] {
            let w = Int(Double(shot.width) * scale), h = Int(Double(shot.height) * scale)
            let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            ctx.interpolationQuality = .medium
            ctx.draw(shot, in: CGRect(x: 0, y: 0, width: w, height: h))
            let out = NSMutableData()
            let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            let jpeg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(out, nil)), 0, nil))
            let payload = PictureInvite.read(jpeg)
            print("JPEG quality \(quality) scale \(scale): \(payload != nil ? "opened" : "FAILED")")
            XCTAssertEqual(try payload.map { try PictureInvite.unlock($0, password: password).phrase }, phrase, "quality \(quality) scale \(scale)")
        }
    }

    func testAScreenshotWithoutAnInviteOpensNothing() throws {
        // Some other night picture: same painter, no stars carrying data.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1206, height: 2622, bitsPerComponent: 8, bytesPerRow: 1206 * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(gray: 0.05, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 1206, height: 2622))
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<4000 {
            ctx.setFillColor(gray: .random(in: 0.3...1, using: &rng), alpha: 1)
            ctx.fill(CGRect(x: .random(in: 72...1134, using: &rng), y: .random(in: 900...2300, using: &rng), width: 2, height: 2))
        }
        XCTAssertNil(PictureInvite.read(try XCTUnwrap(ctx.makeImage())))
    }

    /// A real screenshot of DLChat's invite screen, from GroupListUITests. Run with
    /// DLCHAT_SCREENSHOT=/path/shot.png DLCHAT_SCREENSHOT_PASSWORD="Password: a b c d" swift test ...
    func testOpensARealScreenshot() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["DLCHAT_SCREENSHOT"], let label = env["DLCHAT_SCREENSHOT_PASSWORD"] else { throw XCTSkip("set DLCHAT_SCREENSHOT") }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let shot = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let payload = try XCTUnwrap(PictureInvite.read(shot), "\(shot.width)x\(shot.height) screenshot did not open")
        let opened = try PictureInvite.unlock(payload, password: label.replacingOccurrences(of: "Password:", with: ""))
        print("REAL screenshot \(shot.width)x\(shot.height) opened: \(opened.phrase.words.count)-word phrase")
    }
}
