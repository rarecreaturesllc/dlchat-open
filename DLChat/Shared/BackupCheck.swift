import SwiftUI

/// Compares a copy of the phrase typed from paper with the group's phrase, saying
/// only whether it matches or which word numbers differ. The phrase itself is never shown.
enum BackupCheck {
    enum Result: Equatable {
        case matches
        case wordCount(typed: Int, expected: Int)
        case differ([Int])  // 1-based word numbers
    }

    static func compare(typed: String, phrase: String) -> Result {
        func words(_ text: String) -> [String] { text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) }
        let mine = words(typed), real = words(phrase)
        guard mine.count == real.count else { return .wordCount(typed: mine.count, expected: real.count) }
        let wrong = zip(mine, real).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset + 1 }
        return wrong.isEmpty ? .matches : .differ(wrong)
    }

    static func message(_ result: Result) -> String {
        switch result {
        case .matches:
            return "Your copy matches. Keep it somewhere safe and private."
        case .wordCount(let typed, let expected):
            return "Your copy has \(typed) words. This group's phrase has \(expected)."
        case .differ(let numbers):
            let list = numbers.map(String.init).joined(separator: ", ")
            return numbers.count == 1 ? "Word \(list) is different. Check it on your paper." : "Words \(list) are different. Check them on your paper."
        }
    }
}

/// The sheet: type the words from paper, check, never see the phrase.
struct BackupCheckView: View {
    let phrase: String
    let done: () -> Void
    @State private var typed = ""
    @State private var result: BackupCheck.Result?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text("Check my written copy").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    Text("Type the words from your paper. DLChat says whether they match, without showing the phrase.")
                        .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                    TextField("Words from your paper", text: $typed, axis: .vertical)
                        .focused($focused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .submitLabel(.done).onSubmit(check)
                        .onChange(of: typed) { _, _ in result = nil }
                        .dlField(focused: focused) { focused = true }
                        .accessibilityIdentifier("backup-check-field")
                    Button("Check", action: check).buttonStyle(.dlPrimary)
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("backup-check")
                    if let result {
                        Label(BackupCheck.message(result), systemImage: result == .matches ? "checkmark.seal" : "exclamationmark.triangle")
                            .font(.dl(.headline)).foregroundStyle(result == .matches ? Color.dlGo : Color.dlWarn)
                            .accessibilityIdentifier("backup-check-result")
                    }
                }
                .padding(DLSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private func check() {
        focused = false
        let outcome = BackupCheck.compare(typed: typed, phrase: phrase)
        result = outcome
        UIAccessibility.post(notification: .announcement, argument: BackupCheck.message(outcome))
        if outcome == .matches { Haptics.success() } else { Haptics.warn() }
    }
}
