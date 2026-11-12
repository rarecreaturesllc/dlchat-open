import DLCore
import SwiftUI

/// The radio-rules notice. `onContinue` is set for the first-use gate; without it the notice is read-only.
struct RadioNoticeView: View {
    var onContinue: (() -> Void)?
    /// The continue button's words; turning the Meshtastic radio on asks for an explicit acceptance.
    var continueTitle = "I understand, continue"
    /// Shown after the notice's paragraphs, before the buttons.
    var extra: String?
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.md) {
                HStack {
                    Text(RadioNotice.title).font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("radio-notice-title")
                    Spacer()
                    if onContinue == nil {
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                            .accessibilityIdentifier("radio-notice-done")
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSpace.md) {
                        ForEach(RadioNotice.paragraphs, id: \.self) {
                            Text($0).font(.dl(.body)).foregroundStyle(Color.dlSoft)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // Outside the scroll, right above the button, so what is being accepted is always in view.
                if let extra {
                    Text(extra).font(.dl(.callout, .semibold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("radio-notice-extra")
                }
                if let onContinue {
                    Button(continueTitle, action: onContinue)
                        .buttonStyle(.dlPrimary).accessibilityIdentifier("radio-notice-continue")
                    Button("Not now") { Haptics.tap(); done() }
                        .font(.dl(.headline)).foregroundStyle(Color.dlSoft).frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("radio-notice-cancel")
                }
            }
            .padding(DLSpace.md)
        }
        .preferredColorScheme(.dark)
    }
}

/// Practice send and receive with no radio and no real group (see `PracticeModel`).
struct PracticeView: View {
    let done: () -> Void
    @State private var model = PracticeModel()
    @FocusState private var focused: Bool
    @State private var wordStep = 0
    @ScaledMetric(relativeTo: .largeTitle) private var wordSize = 48
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.md) {
                HStack {
                    Text("Practice").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                    Spacer()
                    Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                        .accessibilityIdentifier("practice-close")
                }
                switch model.step {
                case .intro: intro
                case .say: say
                case .listen: listen
                case .done: finished
                }
            }
            .padding(DLSpace.md)
        }
        .preferredColorScheme(.dark)
        .task { if Launch().screen == .practice { await model.begin() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DLSpace.md) {
            Text("Try it without a radio").font(.dl(.title, .bold)).foregroundStyle(Color.dlText)
            Text("You will read a short practice message out as words, then type the words back the way a listener would. It uses a throwaway phrase made just for this drill. Your groups and messages are not touched and nothing is saved or sent.")
                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
            if let problem = model.problem {
                Text(problem).font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
            }
            Spacer(minLength: 0)
            Button(model.preparing ? "Getting ready…" : "Start the drill") { Task { await model.begin() } }
                .buttonStyle(.dlPrimary).disabled(model.preparing).accessibilityIdentifier("practice-start")
        }
    }

    private var say: some View {
        let groups = model.words.chunked(3)
        let i = min(wordStep, max(groups.count - 1, 0))
        return VStack(spacing: DLSpace.md) {
            Text("1. Say the words").font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("On a real send you would read these aloud, a few at a time.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).frame(maxWidth: .infinity, alignment: .leading)
            SegmentMeter(step: i + 1, total: max(groups.count, 1))
                .accessibilityLabel("Progress").accessibilityValue("\(i + 1) of \(groups.count)")
            Spacer(minLength: 0)
            if groups.indices.contains(i) {
                VStack(spacing: DLSpace.md) {
                    ForEach(Array(groups[i].enumerated()), id: \.offset) { _, w in
                        Text(w).font(.custom("Manrope", fixedSize: wordSize).weight(.bold))
                            .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(Color.dlText)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(groups[i].joined(separator: " "))
                .accessibilityIdentifier("practice-words")
            }
            Spacer(minLength: 0)
            HStack(spacing: DLSpace.sm) {
                Button("Back") { withAnimation(DLMotion.move) { wordStep = max(0, i - 1) } }
                    .buttonStyle(.dlSecondary).frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 140).disabled(i == 0)
                if i < groups.count - 1 {
                    Button("Next") { withAnimation(DLMotion.move) { wordStep = i + 1 } }
                        .buttonStyle(.dlPrimary).accessibilityIdentifier("practice-next")
                } else {
                    Button("Now listen") { focused = false; model.startListening() }
                        .buttonStyle(.dlPrimary).accessibilityIdentifier("practice-listen")
                }
            }
        }
    }

    private var listen: some View {
        VStack(spacing: DLSpace.sm) {
            Text("2. Type what you heard").font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Type each word. If you missed one, tap \"Missed one\" and DLChat will fill it in.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.sm) {
                    Text("\(model.entered.count) of \(model.words.count) words")
                        .font(.dl(.headline)).foregroundStyle(Color.dlSoft).accessibilityIdentifier("practice-count")
                    if model.gaps > 1 {
                        Text("\(model.gaps) words are missing or not on the list. Only one can be filled in.")
                            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                    }
                    if !model.entered.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DLSpace.xs)], spacing: DLSpace.xs) {
                            ForEach(model.entered.indices, id: \.self) { i in
                                let word = model.entered[i]
                                WordChip(word: word, missing: word == Repair.missingMarker || WordList.index(of: word) == nil)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DLSpace.xs) {
                        ForEach(model.suggestions, id: \.self) { s in
                            Button { Haptics.tap(); model.add(s); focused = true } label: {
                                Text(s).font(.dl(.headline)).foregroundStyle(Color.dlText)
                                    .padding(.horizontal, DLSpace.md).frame(minHeight: DLSize.control)
                                    .background(Color.dlPanel, in: RoundedRectangle.key)
                            }
                            .buttonStyle(.dlPress)
                        }
                    }
                }
            }
            TextField("Type a word you heard", text: Bindable(model).typed)
                .focused($focused).submitLabel(.next)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .onChange(of: model.typed) { model.ingestTyped() }
                .onSubmit { model.submit(); focused = true }
                .dlField(focused: focused) { focused = true }
                .accessibilityIdentifier("practice-field")
            ButtonPair {
                Button("Missed one") { model.addMissing() }.buttonStyle(.dlSecondary).accessibilityLabel("Missed a word")
                    .accessibilityIdentifier("practice-missed")
            } second: {
                Button("Undo") { model.undo() }.buttonStyle(.dlSecondary).disabled(model.entered.isEmpty)
            }
            if !focused {
                Button("See the words again") { Haptics.tap(); model.backToWords() }
                    .font(.dl(.headline)).foregroundStyle(Color.dlSoft).frame(minHeight: DLSize.control)
            }
        }
        .contentShape(Rectangle()).onTapGesture { focused = false }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: DLSpace.md) {
            Text("You got it").font(.dl(.title, .bold)).foregroundStyle(Color.dlGo)
            Text(model.decoded ?? "").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                .accessibilityIdentifier("practice-decoded")
            if let note = model.repairNote {
                Label(note, systemImage: "wrench.and.screwdriver")
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo)
            } else {
                Label("Verified", systemImage: "checkmark.seal")
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo)
            }
            Text("That is the whole loop: the sender reads words, the listener types them, and only the right phrase turns them back into the message. Nothing used a radio.")
                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
            Spacer(minLength: 0)
            Button("Practice again") { wordStep = 0; Task { await model.restart() } }
                .buttonStyle(.dlSecondary).accessibilityIdentifier("practice-again")
            Button("Done", action: done).buttonStyle(.dlPrimary).accessibilityIdentifier("practice-done")
        }
    }
}
