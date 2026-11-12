import CoreGraphics
import Foundation

/// Reading a picture invite out of a screenshot or a resized copy: the picture sits somewhere inside a
/// bigger image, smaller than it was made. Find its box from the fine star dust that only the painted
/// sky has, then sample the data spots through that box, nudging position and scale until the stars
/// stand out best. Reed-Solomon has the last word, so a wrong guess never opens.
extension PictureInvite {
    static func readLocated(_ image: CGImage) -> [UInt8]? {
        guard let gray = Gray(image), let located = locate(gray) else { return nil }
        let step = max(1.0, located.scale * 2)
        // The dust's top edge and width are loose guesses: JPEG softens the sky's first rows (often
        // 5-10 px low), text just above can join the run (tens of px high), and a dark stretch of sky at
        // one side cuts the width short (up to about 5%; ringing only ever adds a pixel or two).
        // Sweep top and scale together for where the stars line up, coarsely, before the nudge.
        var coarse = (separation: -Double.infinity, y: located.y, scale: located.scale)
        for ds in stride(from: -0.02, through: 0.08, by: 0.02) {
            let scale = located.scale * (1 + ds)
            for dy in stride(from: -12.0, through: 96.0, by: step) {
                for dx in stride(from: -6.0, through: 6.0, by: step * 2) {
                    let s = separation(contrasts(gray, x: located.x + dx, y: located.y + dy, scale: scale, every: 8))
                    if s > coarse.separation { coarse = (s, located.y + dy, scale) }
                }
            }
        }
        let box = (x: located.x, y: coarse.y, scale: coarse.scale)
        // Nudge: the box is now within a few pixels; the stars settle the rest.
        // Score every guess on a quarter of the spots, then read the best few in full.
        var guesses: [(separation: Double, x: Double, y: Double, scale: Double)] = []
        for ds in stride(from: -0.02, through: 0.02, by: 0.005) {
            let scale = box.scale * (1 + ds)
            for dy in stride(from: -6.0, through: 6.0, by: step) {
                for dx in stride(from: -6.0, through: 6.0, by: step) {
                    let c = contrasts(gray, x: box.x + dx, y: box.y + dy, scale: scale, every: 4)
                    guesses.append((separation(c), box.x + dx, box.y + dy, scale))
                }
            }
        }
        for g in guesses.sorted(by: { $0.separation > $1.separation }).prefix(5) {
            if let codeword = codeword(from: contrasts(gray, x: g.x, y: g.y, scale: g.scale)),
               let payload = ReedSolomon.decode(codeword, parity: parity), payload.first == version { return payload }
        }
        return nil
    }

    /// The picture's top-left corner and its scale (shown width / 1200), from the star dust.
    static func locate(_ gray: Gray) -> (x: Double, y: Double, scale: Double)? {
        // A speck: a pixel brighter than its four neighbours. Flat screen backgrounds have none;
        // text strokes rarely do; the painted sky has thousands.
        var columns = [Int](repeating: 0, count: gray.width), speck = [Bool](repeating: false, count: gray.width * gray.height)
        for y in 1..<(gray.height - 1) {
            for x in 1..<(gray.width - 1) {
                let v = Int(gray[x, y])
                if v > Int(gray[x - 1, y]) + 3, v > Int(gray[x + 1, y]) + 3, v > Int(gray[x, y - 1]) + 3, v > Int(gray[x, y + 1]) + 3 {
                    speck[y * gray.width + x] = true
                    columns[x] += 1
                }
            }
        }
        guard let (left, right) = span(columns), right - left > 100 else { return nil }
        var rows = [Int](repeating: 0, count: gray.height)
        for y in 0..<gray.height { for x in left...right where speck[y * gray.width + x] { rows[y] += 1 } }
        guard let (top, _) = span(rows, longest: true) else { return nil }
        let scale = Double(right - left + 1) / Double(width)
        guard Double(top) + Double(height) * scale <= Double(gray.height) + 8 else { return nil }
        return (Double(left), Double(top), scale)
    }

    /// Where the smoothed counts reach a third of their typical high level: from the first such index
    /// to the last, or (`longest`) the longest run, bridging gaps under `gap`. The longest run, for
    /// rows: text just above the picture (worse after JPEG ringing) makes a short run of its own.
    private static func span(_ counts: [Int], longest: Bool = false, gap: Int = 24) -> (Int, Int)? {
        let r = 4
        let smooth = counts.indices.map { i in counts[max(0, i - r)...min(counts.count - 1, i + r)].reduce(0, +) }
        let high = smooth.sorted()[smooth.count * 9 / 10]
        guard high > 0 else { return nil }
        let cut = Double(high) / 3
        let hits = smooth.indices.filter { Double(smooth[$0]) >= cut }
        guard var first = hits.first, var last = hits.last else { return nil }
        if longest {
            var runs: [(Int, Int)] = [], start = first, prev = first
            for i in hits.dropFirst() {
                if i - prev > gap { runs.append((start, prev)); start = i }
                prev = i
            }
            runs.append((start, prev))
            (first, last) = runs.max { $0.1 - $0.0 < $1.1 - $1.0 }!
        }
        return (max(0, first - r / 2), min(counts.count - 1, last + r / 2))
    }

    /// The same measure as `contrasts(_:)`, sampled through a box instead of a redraw.
    static func contrasts(_ gray: Gray, x ox: Double, y oy: Double, scale s: Double, every: Int = 1) -> [Double] {
        let ring = (0..<12).map { k -> (Double, Double) in
            let a = Double(k) * .pi / 6
            return ((cos(a) * 10).rounded(), (sin(a) * 10).rounded())
        }
        return stride(from: 0, to: codewordBytes * 8, by: every).map { starPoints[$0] }.map { point in
            let px = Double(Int(point.x.rounded())), py = Double(Int(point.y.rounded()))
            func at(_ dx: Double, _ dy: Double) -> Double { gray.sample(ox + (px + dx + 0.5) * s - 0.5, oy + (py + dy + 0.5) * s - 0.5) }
            var core = 0.0
            for dy in -1...1 { for dx in -1...1 { core += at(Double(dx), Double(dy)) } }
            let around = ring.map { at($0.0, $0.1) }.sorted()
            return core / 9 - (around[2] + around[3]) / 2
        }
    }

    /// How well the spots split into stars and sky: the gap between the brighter and darker halves.
    static func separation(_ contrast: [Double]) -> Double {
        let sorted = contrast.sorted(), half = sorted.count / 2
        return sorted[half...].reduce(0, +) / Double(sorted.count - half) - sorted[..<half].reduce(0, +) / Double(half)
    }

    /// Luma of an image at its own size (halved until it is at most 4000 pixels on a side).
    struct Gray {
        let width: Int, height: Int
        private let pixels: [UInt8]

        init?(_ image: CGImage) {
            var w = image.width, h = image.height
            while max(w, h) > 4000 { w /= 2; h /= 2 }
            guard w > 200, h > 200 else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h)
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            width = w; height = h; pixels = buffer
        }

        subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

        /// Bilinear, clamped at the edges.
        func sample(_ x: Double, _ y: Double) -> Double {
            let cx = min(max(x, 0), Double(width - 1)), cy = min(max(y, 0), Double(height - 1))
            let x0 = Int(cx), y0 = Int(cy), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let fx = cx - Double(x0), fy = cy - Double(y0)
            let top = Double(self[x0, y0]) * (1 - fx) + Double(self[x1, y0]) * fx
            let bottom = Double(self[x0, y1]) * (1 - fx) + Double(self[x1, y1]) * fx
            return top * (1 - fy) + bottom * fy
        }
    }
}
