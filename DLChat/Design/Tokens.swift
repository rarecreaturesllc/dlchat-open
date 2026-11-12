import SwiftUI

// Design tokens from DESIGN.md. Change a value there and here together.

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    // "Faceplate" (owner pick 2026-11-10): cool graphite and bone, neon green the one loud colour.
    static let dlWell = Color(hex: 0x040506)      // the recessed readout window
    static let dlNight = Color(hex: 0x0A0C0E)  // graphite: screen background
    static let dlPanel = Color(hex: 0x14181B)  // keys, modules, fields, your own lines in a log
    static let dlHairline = Color(hex: 0x2A3035)  // module edges and log rules
    static let dlEdge = Color(hex: 0x3B4248)  // the bezel of a key
    static let dlText = Color(hex: 0xE1E6E4)  // bone
    static let dlSoft = Color(hex: 0x97A19F)  // secondary text and field edges (7.0:1 on panel)
    static let dlGo = Color(hex: 0x39FF14)        // neon green: the one primary action and live state
    static let dlWarn = Color(hex: 0xFF7366)      // missing word, destructive
}

/// The shape lock: keys, modules and fields 8; anything nested 4pt inside one 4; tags 3. No pills.
/// The only circles are status lights and map points.
enum DLRadius {
    static let tag: CGFloat = 3
    static let inner: CGFloat = 4
    static let key: CGFloat = 8
}

enum DLStroke {
    static let hair: CGFloat = 1     // bezels, module edges, log rules
    static let field: CGFloat = 1.5  // a text field at rest (the Edge Rule)
    static let strong: CGFloat = 2   // focus, a missing word, Increase Contrast
}

/// Short and physical; nothing decorates. Callers pass nil instead when Reduce Motion is on.
enum DLMotion {
    static let press = Animation.spring(duration: 0.2)   // a key going down 3%
    static let move = Animation.snappy(duration: 0.25)   // the tab highlight, a new log line, the next three words
    static let exit = Animation.easeOut(duration: 0.2)   // leaving or settling back: a fifth shorter than `move`, no spring
    static let pressScale: CGFloat = 0.97                // how far a key goes down
}

enum DLSpace {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}

enum DLSize {
    static let control: CGFloat = 48   // smallest tappable thing
    static let primary: CGFloat = 64   // primary and secondary buttons (pills)
}

extension Font {
    /// Manrope (bundled, SIL OFL), scaled with Dynamic Type from each style's default size.
    static func dl(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let w: Font.Weight = (style == .headline && weight == .regular) ? .semibold : weight
        return .custom("Manrope", size: baseSize(style), relativeTo: style).weight(w)
    }

    /// Data and legends (times, counts, status, tab labels): SF Mono, scaled with Dynamic Type.
    static func dlMono(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

extension RoundedRectangle {
    static let key = RoundedRectangle(cornerRadius: DLRadius.key, style: .continuous)
    static let inner = RoundedRectangle(cornerRadius: DLRadius.inner, style: .continuous)
    static let tag = RoundedRectangle(cornerRadius: DLRadius.tag, style: .continuous)
}

extension View {
    /// A legend (tabs, status, readout lines): mono caps. Callers pass the text already uppercased
    /// and keep the accessibility label in normal case: .textCase would also uppercase what VoiceOver reads.
    func dlCaps(_ style: Font.TextStyle = .footnote) -> some View {
        font(.dlMono(style)).tracking(0.4)
    }
}
