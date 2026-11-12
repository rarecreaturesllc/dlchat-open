import SwiftUI

/// The number on a picture invite password box (1 to 6), so both phones agree on the order the words
/// are read out and typed in. Decorative: the box's own label says "Word 1" for VoiceOver.
struct SlotNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.dlMono(.headline, .bold))
            .foregroundStyle(Color.dlNight)
            .frame(minWidth: 30, minHeight: 30)
            .background(Color.dlText, in: RoundedRectangle.inner)
            .accessibilityHidden(true)
    }
}
