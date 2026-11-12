import CommonCrypto
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// A group invite as a picture: a painted night landscape (unique to the group, drawn from a one-way
/// hash of its phrase) whose stars carry the phrase and group name, encrypted with password words the
/// sender reads out by voice. A copy left in Messages or iCloud is useless without them.
///
/// Stars: the upper sky (1200 x 1500 image, top 40%) holds 1,056 fixed spots scattered like real
/// stars, clumped in places. A star is a 1; empty sky or a faint speck is a 0. They carry the payload
/// plus 64 Reed-Solomon bytes, so recompression, blur or a scribbled patch still decode. Star sizes and
/// brightness vary, and more stars continue down to the ridges, so nothing marks where the data ends. The reader rescales any copy back to 1200 x 1500, so a resized image works; a crop does not.
public enum PictureInvite {
    public static let width = 1200
    public static let height = 1500
    /// The sender picks how many words; nothing in the picture or on the unlock screen says which.
    /// At least 5 (50 bits): the picture may sit in a chat backup for years, and 4 words (40 bits) at
    /// 600,000 PBKDF2 rounds falls to about a GPU-year of guessing. Older 4-word pictures still open.
    public static let passwordWordCounts = 5...6

    public enum UnlockError: Error, Equatable {
        case wrongPassword
        case damaged
    }

    // MARK: Password

    /// Random words from the radio word list (10 bits each), to be read to the friend by voice.
    public static func makePassword(words count: Int = 5) -> [String] {
        precondition(passwordWordCounts.contains(count), "unsupported password length")
        var bytes = [UInt8](repeating: 0, count: count * 2)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess, "no randomness")
        // 1024 divides 65536, so taking the low 10 bits has no bias.
        return (0..<count).map { i in
            WordList.word(at: (Int(bytes[2 * i]) << 8 | Int(bytes[2 * i + 1])) % WordList.count)
        }
    }

    /// Lowercase words joined by single spaces, so "Maple  RIVER" and "maple river" unlock alike.
    public static func normalizePassword(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
    }

    // MARK: Picture

    /// The invite picture. Slow (about half a second): the password is stretched like the phrase is.
    public static func render(phrase: Phrase, name: String, password: String) throws -> CGImage {
        let payload = try seal(phrase: phrase, name: name, password: password)
        let bits = ReedSolomon.encode(payload, parity: parity).flatMap { (byte: UInt8) -> [Bool] in (0..<8).map { (byte >> UInt8(7 - $0)) & 1 == 1 } }
        let seed = sceneSeed(phrase)
        let context = makeContext()
        Scene.paint(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height), seed: seed, clearAbove: CGFloat(dataBottom)) {
            paintStars(in: $0, data: bits, seed: seed)
        }
        return context.makeImage()!
    }

    /// The sealed payload from a picture, a screenshot of it or a smaller copy, repaired if needed, or
    /// nil when it is not an invite, the picture itself was cropped, or it is too damaged or too small.
    public static func read(_ image: CGImage) -> [UInt8]? {
        if let codeword = rawCodeword(image),
           let payload = ReedSolomon.decode(codeword, parity: parity), payload.first == version { return payload }
        // Not the picture as made: perhaps a screenshot of it, or a smaller copy.
        return readLocated(image)
    }

    /// The codeword as seen in the stars, before any repair. Tests use it to measure the margin.
    static func rawCodeword(_ image: CGImage) -> [UInt8]? {
        guard let contrast = contrasts(image) else { return nil }
        return codeword(from: contrast)
    }

    /// Each data spot's brightness against the sky around it.
    static func contrasts(_ image: CGImage) -> [Double]? {
        let ratio = Double(image.width) / Double(image.height)
        guard abs(ratio - Double(width) / Double(height)) < 0.02 else { return nil }
        let context = makeContext(flipped: false)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        func luma(_ x: Int, _ y: Int) -> Double {
            let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
            return 0.299 * Double(data[i]) + 0.587 * Double(data[i + 1]) + 0.114 * Double(data[i + 2])
        }
        // Each point: its 3 x 3 core against the darker part of a ring around it, so the sky's gradient,
        // moon glow and neighbouring stars do not count.
        let ring = (0..<12).map { k -> (Int, Int) in
            let a = Double(k) * .pi / 6
            return (Int((cos(a) * 10).rounded()), Int((sin(a) * 10).rounded()))
        }
        let contrast = starPoints.prefix(codewordBytes * 8).map { point -> Double in
            let x = Int(point.x.rounded()), y = Int(point.y.rounded())
            var core = 0.0
            for dy in -1...1 { for dx in -1...1 { core += luma(x + dx, y + dy) } }
            let around = ring.map { luma(x + $0.0, y + $0.1) }.sorted()
            // Lower quartile, not median: in a tight clump bright neighbours fill half the ring.
            return core / 9 - (around[2] + around[3]) / 2
        }
        return contrast
    }

    static func codeword(from contrast: [Double]) -> [UInt8]? {
        // Two-means split: roughly half the points are stars.
        var threshold = contrast.reduce(0, +) / Double(contrast.count)
        var low = 0.0, high = 0.0
        for _ in 0..<8 {
            let on = contrast.filter { $0 > threshold }, off = contrast.filter { $0 <= threshold }
            guard !on.isEmpty, !off.isEmpty else { return nil }
            high = on.reduce(0, +) / Double(on.count)
            low = off.reduce(0, +) / Double(off.count)
            threshold = (high + low) / 2
        }
        guard high - low > 25 else { return nil }
        // Bright stars pull the "on" average up, so the midpoint can sit above the faintest stars.
        // Cut in the middle of the widest gap between the two averages instead.
        let between = contrast.filter { $0 > low && $0 < high }.sorted()
        if between.count > 1 {
            let widest = zip(between, between.dropFirst()).max { $0.1 - $0.0 < $1.1 - $1.0 }!
            threshold = (widest.0 + widest.1) / 2
        }
        let bits = contrast.map { $0 > threshold }
        return stride(from: 0, to: bits.count, by: 8).map { start in
            (0..<8).reduce(UInt8(0)) { $0 << 1 | (bits[start + $1] ? 1 : 0) }
        }
    }

    /// The phrase and group name inside a payload from `read`. Slow, like `render`.
    public static func unlock(_ payload: [UInt8], password: String) throws -> (phrase: Phrase, name: String) {
        guard payload.count == payloadSize, payload[0] == version else { throw UnlockError.damaged }
        let header = Array(payload[0..<headerSize])
        let (key, nonce) = stretch(password: normalizePassword(password), salt: Array(payload[1..<headerSize]))
        guard let box = try? ChaChaPoly.SealedBox(nonce: nonce, ciphertext: payload[headerSize..<(headerSize + plainSize)], tag: payload[(headerSize + plainSize)...]),
              let plain = try? Array(ChaChaPoly.open(box, using: key, authenticating: header))
        else { throw UnlockError.wrongPassword }
        let count = Int(plain[0])
        guard Phrase.lengths.contains(count) else { throw UnlockError.damaged }
        let indices = (0..<count).map { n in
            (0..<10).reduce(0) { value, b in
                let bit = n * 10 + b
                return value << 1 | Int(plain[1 + bit / 8] >> UInt8(7 - bit % 8) & 1)
            }
        }
        guard let phrase = try? Phrase.parse(indices.map(WordList.word(at:)).joined(separator: " ")) else { throw UnlockError.damaged }
        let nameLength = min(Int(plain[nameOffset]), maxNameBytes)
        let name = String(decoding: plain[(nameOffset + 1)..<(nameOffset + 1 + nameLength)], as: UTF8.self)
        return (phrase, name)
    }

    /// PNG bytes for sharing; PNG avoids the first round of JPEG loss.
    public static func pngData(_ image: CGImage) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    // MARK: Payload

    static let version: UInt8 = 2
    static let kdfRounds: UInt32 = 600_000
    static let saltSize = 8
    static let headerSize = 1 + saltSize  // version, salt
    public static let maxNameBytes = 16
    static let nameOffset = 26  // after the word count and 20 ten-bit word numbers (25 bytes)
    static let plainSize = nameOffset + 1 + maxNameBytes  // fixed, so the length says nothing
    static let payloadSize = headerSize + plainSize + 16  // header, sealed text, tag
    static let parity = 64
    static let codewordBytes = payloadSize + parity

    static func seal(phrase: Phrase, name: String, password: String) throws -> [UInt8] {
        var plain = [UInt8](repeating: 0, count: plainSize)
        plain[0] = UInt8(phrase.indices.count)
        for (n, index) in phrase.indices.enumerated() {
            for b in 0..<10 where index >> (9 - b) & 1 == 1 {
                let bit = n * 10 + b
                plain[1 + bit / 8] |= 1 << UInt8(7 - bit % 8)
            }
        }
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.utf8.count > maxNameBytes { trimmed.removeLast() }
        plain[nameOffset] = UInt8(trimmed.utf8.count)
        plain.replaceSubrange((nameOffset + 1)..<(nameOffset + 1 + trimmed.utf8.count), with: trimmed.utf8)
        var salt = [UInt8](repeating: 0, count: saltSize)
        precondition(SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess, "no randomness")
        let header = [version] + salt
        let (key, nonce) = stretch(password: normalizePassword(password), salt: salt)
        let box = try ChaChaPoly.seal(plain, using: key, nonce: nonce, authenticating: header)
        return header + Array(box.ciphertext) + Array(box.tag)
    }

    /// Key and nonce from the password. The salt is fresh for every picture, so the pair never repeats
    /// and the nonce need not be stored.
    static func stretch(password: String, salt: [UInt8]) -> (SymmetricKey, ChaChaPoly.Nonce) {
        let bytes = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: 44)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), bytes.map { Int8(bitPattern: $0) }, bytes.count, salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), kdfRounds, &out, out.count)
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return (SymmetricKey(data: out[0..<32]), try! ChaChaPoly.Nonce(data: out[32..<44]))
    }

    // MARK: Stars

    static let dataTop = 10.0
    static let dataBottom = 612.0
    static let skyBottom = 1000.0  // filler stars continue down behind the ridges, so no edge shows

    /// Star spots, data first, in reading order. Scattered like real stars (tighter in a few fixed
    /// clumps, never closer than 15 px), the same on every device: plain arithmetic, no libm calls.
    /// Data spots are read in bands of 24 px, left to right, so a damaged patch spoils few bytes.
    static let starPoints: [CGPoint] = {
        var rng = SplitMix(seed: 0x57A2_F1E1_D000_0003)
        let clumps = (0..<9).map { _ in (x: rng.range(0, 1200), y: rng.range(0, skyBottom), s: rng.range(120, 320)) }
        func spacing(_ x: Double, _ y: Double) -> Double {
            var w = 0.0
            for c in clumps {
                let dx = x - c.x, dy = y - c.y
                w += 1 / (1 + (dx * dx + dy * dy) / (c.s * c.s))
            }
            return 25 - 10 * min(w, 1)
        }
        let bucket = 13.0, columns = Int(Double(width) / bucket) + 3
        var buckets: [Int: [Int]] = [:]
        var points: [CGPoint] = []
        func place(top: Double, bottom: Double, count: Int?, attempts: Int) {
            var placed = 0
            for _ in 0..<attempts {
                if let count, placed == count { return }
                let x = rng.range(6, Double(width) - 6), y = rng.range(top, bottom), d = spacing(x, y)
                let bx = Int(x / bucket), by = Int(y / bucket)
                var clear = true
                search: for gy in (by - 2)...(by + 2) { for gx in (bx - 2)...(bx + 2) {
                    for i in buckets[gy * columns + gx] ?? [] {
                        let dx = points[i].x - x, dy = points[i].y - y
                        if dx * dx + dy * dy < d * d { clear = false; break search }
                    }
                } }
                guard clear else { continue }
                buckets[by * columns + bx, default: []].append(points.count)
                points.append(CGPoint(x: x, y: y))
                placed += 1
            }
            precondition(count == nil || placed == count, "sky too small")
        }
        let needed = codewordBytes * 8
        place(top: dataTop, bottom: dataBottom - 12, count: needed, attempts: 2_000_000)
        let data = points.sorted { a, b in
            let ra = Int(a.y / 24), rb = Int(b.y / 24)
            return ra != rb ? ra < rb : a.x < b.x
        }
        place(top: dataBottom - 12, bottom: skyBottom, count: nil, attempts: 40_000)
        return data + points.dropFirst(needed)
    }()

    private static func paintStars(in context: CGContext, data: [Bool], seed: UInt64) {
        // Looks come from the group, never from the data, so the rest of the painting stays the group's.
        var looks = SplitMix(seed: seed ^ 0x5747_5253)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let tints = [Scene.RGB(0xFFFFFF), Scene.RGB(0xFFF1D6), Scene.RGB(0xDCE8FF), Scene.RGB(0xFFE3C4)]
        for (n, point) in starPoints.enumerated() {
            // Every spot draws the same numbers whatever its bit, so the data never shifts the looks.
            let tint = tints[Int(looks.next() % UInt64(tints.count))]
            let bright = looks.unit() < 0.07
            let radius = bright ? looks.range(2.6, 3.4) : looks.range(1.3, 2.2)
            let alpha = looks.range(0.7, 1.0)
            let filler = looks.next() & 1 == 1
            // A 0 is empty sky or a speck far too faint to read as a 1, so there is no on/off pattern.
            let speck = looks.unit() < 0.6, speckRadius = looks.range(0.5, 0.9), speckAlpha = looks.range(0.1, 0.3)
            if n < data.count ? data[n] : filler {
                let glow = CGGradient(colorsSpace: space, colors: [tint.color(bright ? 0.5 : 0.3), tint.color(0)] as CFArray, locations: [0, 1])!
                context.drawRadialGradient(glow, startCenter: point, startRadius: radius * 0.6, endCenter: point, endRadius: radius * (bright ? 3.5 : 2.5), options: [])
                context.setFillColor(tint.color(alpha))
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            } else if speck {
                context.setFillColor(tint.color(speckAlpha))
                context.fillEllipse(in: CGRect(x: point.x - speckRadius, y: point.y - speckRadius, width: speckRadius * 2, height: speckRadius * 2))
            }
        }
    }

    /// Bitmap row 0 is the image's top row. `flipped` gives drawing code a top-left origin to match;
    /// reading draws the image unflipped so it lands the right way up.
    private static func makeContext(flipped: Bool = true) -> CGContext {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if flipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        return context
    }

    static func sceneSeed(_ phrase: Phrase) -> UInt64 {
        let digest = SHA256.hash(data: Data("DLChat/v1/scene \(phrase.text)".utf8))
        return digest.prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }
}

/// Small deterministic generator, so a group's scene is the same on every phone.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}
