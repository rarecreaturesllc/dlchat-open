import CoreGraphics
import Foundation

/// Paints a night landscape from a seed: one of three night skies, a faint Milky Way, the stars the
/// caller paints, a low moon, ridges that fade into haze with distance, sometimes a lake with
/// reflections, pines on the near ridge, and fine grain. Same seed, same picture. Top-left origin.
/// Nothing but sky and stars is drawn above `clearAbove`, so the caller's stars stay readable.
enum Scene {
    private struct Palette {
        var skyTop, skyMid, horizon, light, far, near: RGB
    }

    struct RGB {
        var r, g, b: Double
        func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
        func color(_ alpha: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: alpha) }
        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        init(_ hex: UInt32) { self.init(r: Double(hex >> 16 & 0xFF) / 255, g: Double(hex >> 8 & 0xFF) / 255, b: Double(hex & 0xFF) / 255) }
    }

    private static let palettes: [Palette] = [
        // deep night, last light of dusk, first light of dawn: dark above, any glow low on the horizon
        Palette(skyTop: RGB(0x040917), skyMid: RGB(0x0E1D3D), horizon: RGB(0x2F4C7D), light: RGB(0xF4F1E2), far: RGB(0x2C3D61), near: RGB(0x0A0F1E)),
        Palette(skyTop: RGB(0x07061A), skyMid: RGB(0x1F1640), horizon: RGB(0xB0584A), light: RGB(0xFFE2B8), far: RGB(0x4A3560), near: RGB(0x120C20)),
        Palette(skyTop: RGB(0x030B18), skyMid: RGB(0x0F2640), horizon: RGB(0x5E8C9A), light: RGB(0xEAF4F0), far: RGB(0x2A4A5A), near: RGB(0x081419)),
    ]

    static func paint(in context: CGContext, rect r: CGRect, seed: UInt64, clearAbove: CGFloat, stars: (CGContext) -> Void) {
        var rng = SplitMix(seed: seed)
        var p = palettes[Int(rng.next() % UInt64(palettes.count))]
        // Nudge every colour a little so two dusks are not the same dusk.
        let shift = RGB(r: rng.range(-0.03, 0.03), g: rng.range(-0.03, 0.03), b: rng.range(-0.03, 0.03))
        for keyPath in [\Palette.skyTop, \.skyMid, \.horizon, \.far, \.near] {
            let c = p[keyPath: keyPath]
            p[keyPath: keyPath] = RGB(r: min(max(c.r + shift.r, 0), 1), g: min(max(c.g + shift.g, 0), 1), b: min(max(c.b + shift.b, 0), 1))
        }
        let hasLake = rng.unit() < 0.55
        let horizonY = r.minY + r.height * rng.range(0.50, 0.58)
        let lakeTop = r.minY + r.height * rng.range(0.66, 0.74)

        context.saveGState()
        context.clip(to: r)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        // Sky.
        let skyEnd = horizonY + r.height * 0.06
        let darkUntil = (clearAbove - r.minY) / (skyEnd - r.minY)
        let sky = CGGradient(colorsSpace: space, colors: [p.skyTop.color(), p.skyMid.color(), p.horizon.color()] as CFArray, locations: [0, darkUntil, 1])!
        context.drawLinearGradient(sky, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: skyEnd), options: [.drawsAfterEndLocation])

        // Milky Way: a faint band of soft haze across the sky at a slant.
        let bandY0 = r.minY + rng.range(0.05, 0.35) * clearAbove, bandY1 = r.minY + rng.range(0.4, 0.9) * clearAbove
        for _ in 0..<60 {
            let t = rng.unit()
            let x = r.minX + t * r.width, y = bandY0 + (bandY1 - bandY0) * t + rng.range(-1, 1) * r.height * 0.04
            let w = r.width * rng.range(0.08, 0.2), h = w * rng.range(0.3, 0.6)
            context.setFillColor(p.light.mix(p.skyMid, 0.3).color(rng.range(0.015, 0.035)))
            context.fillEllipse(in: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
        }
        // Star dust thick along the band and thin elsewhere, so the sky clumps like a real one.
        for _ in 0..<2200 {
            let t = rng.unit(), spread = (rng.unit() + rng.unit() + rng.unit() - 1.5) * r.height * 0.07
            let x = r.minX + t * r.width, y = bandY0 + (bandY1 - bandY0) * t + spread * (rng.unit() < 0.25 ? 4 : 1)
            let size = rng.range(0.6, 1.3)
            context.setFillColor(RGB(0xFFFFFF).color(rng.range(0.12, 0.4)))
            context.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        }

        stars(context)

        // Moon, low: rising behind the ridges, its glow kept out of the starfield.
        let radius = r.width * rng.range(0.035, 0.06)
        let sun = CGPoint(x: r.minX + r.width * rng.range(0.15, 0.85), y: clearAbove + radius * 3 + rng.range(0, max(0, horizonY - clearAbove - radius * 3)))
        let glow = CGGradient(colorsSpace: space, colors: [p.light.color(0.45), p.light.color(0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: sun, startRadius: radius * 0.8, endCenter: sun, endRadius: radius * 3, options: [])
        context.setFillColor(p.light.color())
        context.fillEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))

        // Ridges, far to near, each fading into haze at its foot.
        let layers = Int(rng.range(4, 6))
        let groundY = hasLake ? lakeTop : r.maxY
        var nearRidge: [CGPoint] = []
        for i in 0..<layers {
            let t = Double(i) / Double(layers - 1)
            let base = horizonY + (groundY - horizonY) * (0.15 + 0.6 * t)
            let amplitude = r.height * (0.20 - 0.11 * t) * rng.range(0.7, 1.2)
            var ridge = ridgeLine(from: r.minX, to: r.maxX, base: base, amplitude: amplitude, roughness: 0.52 + 0.08 * t, rng: &rng)
            // Squeeze tall peaks down under the starfield rather than flattening them.
            let limit = clearAbove + r.height * 0.02, peak = ridge.map(\.y).min() ?? CGFloat(base)
            if peak < limit, base > limit {
                ridge = ridge.map { CGPoint(x: $0.x, y: base - (base - $0.y) * (base - limit) / (base - peak)) }
            }
            let path = CGMutablePath()
            path.addLines(between: ridge)
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.closeSubpath()
            let body = p.far.mix(p.near, t)
            let top = body.mix(p.horizon, 0.25 * (1 - t))
            context.saveGState()
            context.addPath(path)
            context.clip()
            let fill = CGGradient(colorsSpace: space, colors: [top.color(), body.color()] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(fill, start: CGPoint(x: r.midX, y: base - amplitude), end: CGPoint(x: r.midX, y: base + r.height * 0.1), options: [.drawsAfterEndLocation])
            context.restoreGState()
            if i < layers - 1 {
                let haze = CGGradient(colorsSpace: space, colors: [p.horizon.color(0), p.horizon.color(0.35)] as CFArray, locations: [0, 1])!
                context.drawLinearGradient(haze, start: CGPoint(x: r.midX, y: base - amplitude * 0.2), end: CGPoint(x: r.midX, y: base + r.height * 0.06), options: [.drawsAfterEndLocation])
            }
            nearRidge = ridge
        }

        // Pines along the near ridge.
        let pine = p.near.mix(RGB(0x000000), 0.35)
        for _ in 0..<Int(rng.range(18, 42)) {
            let point = nearRidge[Int(rng.next() % UInt64(nearRidge.count))]
            let h = r.height * rng.range(0.03, 0.08), w = h * rng.range(0.3, 0.42)
            let y = point.y + h * 0.2
            let tree = CGMutablePath()
            for tier in 0..<3 {
                let top = y - h + Double(tier) * h * 0.25, spread = w * (0.55 + 0.25 * Double(tier))
                tree.move(to: CGPoint(x: point.x, y: top))
                tree.addLine(to: CGPoint(x: point.x + spread, y: top + h * 0.45))
                tree.addLine(to: CGPoint(x: point.x - spread, y: top + h * 0.45))
                tree.closeSubpath()
            }
            tree.addRect(CGRect(x: point.x - w * 0.06, y: y - h * 0.1, width: w * 0.12, height: h * 0.25))
            context.setFillColor(pine.color())
            context.addPath(tree)
            context.fillPath()
        }

        // Lake: sky colours deepening downward, a sun path, the near ridge mirrored, shimmer lines.
        if hasLake {
            let water = CGRect(x: r.minX, y: lakeTop, width: r.width, height: r.maxY - lakeTop)
            context.saveGState()
            context.clip(to: water)
            let deep = CGGradient(colorsSpace: space, colors: [p.horizon.mix(p.skyMid, 0.4).color(), p.skyTop.mix(p.near, 0.5).color()] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(deep, start: CGPoint(x: r.midX, y: lakeTop), end: CGPoint(x: r.midX, y: r.maxY), options: [])
            let mirrored = CGMutablePath()
            mirrored.addLines(between: nearRidge.map { CGPoint(x: $0.x, y: lakeTop + (lakeTop - $0.y) * 0.6) })
            mirrored.addLine(to: CGPoint(x: r.maxX, y: lakeTop))
            mirrored.addLine(to: CGPoint(x: r.minX, y: lakeTop))
            mirrored.closeSubpath()
            context.setFillColor(p.near.color(0.45))
            context.addPath(mirrored)
            context.fillPath()
            for _ in 0..<70 {
                let y = lakeTop + rng.unit() * water.height
                let spread = r.width * rng.range(0.01, 0.07) * (0.4 + (y - lakeTop) / water.height)
                let x = sun.x + rng.range(-1, 1) * r.width * 0.05
                context.setFillColor(p.light.color(rng.range(0.15, 0.5) * (1 - (y - lakeTop) / water.height * 0.6)))
                context.fill(CGRect(x: x - spread, y: y, width: spread * 2, height: 1.6))
            }
            for _ in 0..<40 {
                let y = lakeTop + rng.unit() * water.height, x = r.minX + rng.unit() * r.width
                context.setFillColor(p.horizon.color(0.12))
                context.fill(CGRect(x: x, y: y, width: r.width * rng.range(0.04, 0.15), height: 1.2))
            }
            context.restoreGState()
        }

        // Grain, for a painted rather than flat look.
        for _ in 0..<9000 {
            let x = r.minX + rng.unit() * r.width, y = r.minY + rng.unit() * r.height
            context.setFillColor((rng.unit() < 0.5 ? RGB(0xFFFFFF) : RGB(0x000000)).color(0.05))
            context.fill(CGRect(x: x, y: y, width: 1.4, height: 1.4))
        }
        context.restoreGState()
    }

    /// Midpoint displacement: a jagged skyline across the width.
    private static func ridgeLine(from x0: CGFloat, to x1: CGFloat, base: CGFloat, amplitude: CGFloat, roughness: Double, rng: inout SplitMix) -> [CGPoint] {
        let count = 129
        var heights = [Double](repeating: 0, count: count)
        heights[0] = rng.range(-0.5, 0.5)
        heights[count - 1] = rng.range(-0.5, 0.5)
        var step = count - 1, scale = 1.0
        while step > 1 {
            let half = step / 2
            for i in stride(from: half, to: count, by: step) {
                heights[i] = (heights[i - half] + heights[i + half]) / 2 + rng.range(-1, 1) * scale
            }
            scale *= roughness
            step = half
        }
        return heights.enumerated().map { i, h in
            CGPoint(x: x0 + (x1 - x0) * CGFloat(i) / CGFloat(count - 1), y: base - amplitude * (0.5 + 0.5 * h))
        }
    }
}
