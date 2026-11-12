import DLCore
import SwiftUI

/// The eight call sign colours (DLCore `CallSign.color` 0-7). Light enough that the letters,
/// in obsidian ink, read clearly on each one.
enum CallSignPalette {
    static let colors: [(name: String, color: Color)] = [
        ("Bone", Color(hex: 0xE8E6DF)),
        ("Amber", Color(hex: 0xF2B84B)),
        ("Sky", Color(hex: 0x7CC0FF)),
        ("Rose", Color(hex: 0xFF9DBB)),
        ("Violet", Color(hex: 0xC0A8FF)),
        ("Teal", Color(hex: 0x5ED6C9)),
        ("Orange", Color(hex: 0xFFA868)),
        ("Lime", Color(hex: 0xC2EE6A)),
    ]

    static func color(_ index: Int) -> Color { colors.indices.contains(index) ? colors[index].color : colors[0].color }
    static func name(_ index: Int) -> String { colors.indices.contains(index) ? colors[index].name : colors[0].name }
}

/// A call sign as a small coloured tag: on a friend's Chat message, and as the preview in Settings.
struct CallSignBadge: View {
    let sign: CallSign
    var style: Font.TextStyle = .caption

    var body: some View {
        Text(sign.letters)
            .font(.dl(style, .bold)).tracking(1)
            .foregroundStyle(Color.dlNight)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(CallSignPalette.color(sign.color), in: RoundedRectangle.tag)
            .accessibilityLabel("Call sign \(sign.letters.map(String.init).joined(separator: " "))")
    }
}

/// Settings > Call sign: letters and a colour, saved in the sealed store as they change.
struct CallSignEditor: View {
    let groups: GroupModel
    @State private var letters = ""
    @State private var color = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            HStack(spacing: DLSpace.sm) {
                // The system placeholder grey fails the contrast audit on the panel, so it uses the soft text colour.
                TextField("", text: $letters, prompt: Text("e.g. HF").foregroundStyle(Color.dlSoft))
                    .focused($focused)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().submitLabel(.done)
                    .dlField(focused: focused) { focused = true }
                    .accessibilityLabel("Call sign letters")
                    .accessibilityIdentifier("settings-callsign-field")
                if let sign = CallSign(letters, color: color) {
                    CallSignBadge(sign: sign, style: .headline)
                        .accessibilityIdentifier("settings-callsign-preview")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DLSpace.xs), count: 4), spacing: DLSpace.xs) {
                ForEach(CallSignPalette.colors.indices, id: \.self) { index in
                    Button { Haptics.tap(); color = index; save() } label: {
                        RoundedRectangle.inner.fill(CallSignPalette.color(index)).frame(width: 30, height: 30)
                            .overlay { if color == index { RoundedRectangle.inner.stroke(Color.dlText, lineWidth: 3).padding(-5) } }
                            .frame(maxWidth: .infinity, minHeight: DLSize.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CallSignPalette.name(index))
                    .accessibilityAddTraits(color == index ? .isSelected : [])
                    .accessibilityIdentifier("settings-callsign-color-\(index)")
                }
            }
            if groups.callSign != nil {
                Button("Remove call sign") { Haptics.tap(); letters = ""; save() }
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn).frame(minHeight: DLSize.control)
                    .accessibilityIdentifier("settings-callsign-remove")
            }
        }
        .onAppear {
            letters = groups.callSign?.letters ?? ""
            color = groups.callSign?.color ?? 0
        }
        .onChange(of: letters) { _, typed in
            let cleaned = CallSign.clean(typed)
            if cleaned != typed { letters = cleaned } else { save() }
        }
        .onChange(of: groups.wipes) { _, _ in letters = ""; color = 0 }
    }

    private func save() {
        let sign = CallSign(letters, color: color)
        if sign != groups.callSign { groups.setCallSign(sign) }
    }
}
