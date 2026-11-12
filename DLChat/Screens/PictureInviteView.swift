import DLCore
import SwiftUI

/// The first two steps of a new group, shown right on New group: (1) send the painted picture, whose
/// stars hold the phrase, (2) say the Picture Password words out loud. The picture can travel any way;
/// without the spoken words it opens nothing. Step 3 (the safety words) lives in GroupSetupView.
struct PictureInviteSteps: View {
    let phrase: Phrase
    let name: String

    @State private var wordCount = 5
    @State private var password = PictureInvite.makePassword()
    @State private var image: CGImage?
    @State private var file: URL?

    /// What the picture is made from. The picture is painted again when any of it changes.
    private struct Source: Equatable {
        var phrase: String
        var name: String
        var password: [String]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.lg) {
            VStack(alignment: .leading, spacing: DLSpace.sm) {
                WalkthroughStep(number: 1, title: "Send the picture", systemImage: "photo")
                if let image {
                    Image(image, scale: 1, label: Text("A painted night landscape. Its stars hold the locked group phrase."))
                        .resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle.key)
                        .accessibilityIdentifier("picture-invite")
                } else {
                    // Stretching the password takes about half a second.
                    RoundedRectangle.key.fill(Color.dlPanel)
                        .aspectRatio(CGFloat(PictureInvite.width) / CGFloat(PictureInvite.height), contentMode: .fit)
                        .overlay { ProgressView().tint(Color.dlSoft) }
                        .accessibilityLabel("Painting the picture")
                }
                if let file {
                    ShareLink(item: file) { Text("Share the picture") }
                        .buttonStyle(.dlPrimary).accessibilityIdentifier("share-picture")
                }
                Text("Send it any way you like: Messages, AirDrop, email. On its own the picture opens nothing, even if Messages or iCloud keeps a copy.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }

            VStack(alignment: .leading, spacing: DLSpace.sm) {
                WalkthroughStep(number: 2, title: "Say your Picture Password", systemImage: "key.fill")
                DLSegments(selection: $wordCount, options: Array(PictureInvite.passwordWordCounts)) { "\($0) words" }
                .accessibilityIdentifier("password-length")
                .onChange(of: wordCount) { password = PictureInvite.makePassword(words: wordCount) }
                // Hidden until held, so the screen never shows the picture and its password together.
                HoldToReveal(title: "Hold for your Picture Password") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DLSpace.xs), count: 2), spacing: DLSpace.xs) {
                        // Numbered so the friend types each word into the same numbered box.
                        ForEach(Array(password.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: DLSpace.xs) {
                                SlotNumber(number: index + 1)
                                Text(word).font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, DLSpace.sm)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.dlPanel, in: RoundedRectangle.key)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Password: \(password.joined(separator: " "))")
                    .accessibilityIdentifier("picture-password")
                }
                Text("Read the words out loud, 1 first, by phone or in person. Your friend opens the picture in DLChat under Join, Open a picture invite, and types each word into the box with the same number. Never write the words in the same message as the picture. More words is harder to guess; the picture does not say how many there are.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
        }
        .task(id: Source(phrase: phrase.text, name: name, password: password)) {
            // Typing a group name changes the picture: wait for a pause before painting it again.
            if image != nil {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            image = nil
            if let file { try? FileManager.default.removeItem(at: file); self.file = nil }
            let phrase = phrase, name = name, password = password.joined(separator: " ")
            guard let made = try? await Task.detached(operation: { try PictureInvite.render(phrase: phrase, name: name, password: password) }).value
            else { return }
            // Something changed while this painted: a newer render owns the picture.
            guard !Task.isCancelled else { return }
            image = made
            let url = FileManager.default.temporaryDirectory.appending(path: "DLChat invite.png")
            if (try? PictureInvite.pngData(made).write(to: url, options: .completeFileProtection)) != nil { file = url }
        }
        // The file is encrypted, but there is no reason to leave it behind.
        .onDisappear { if let file { try? FileManager.default.removeItem(at: file) } }
    }
}

/// A picture invite for a group that already exists (Group details > Make a picture invite): the same
/// three steps as New group, in a sheet.
struct PictureInviteView: View {
    let phrase: Phrase
    let name: String
    let safetyWords: [String]
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Picture invite").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                    }
                    PictureInviteSteps(phrase: phrase, name: name)
                    VStack(alignment: .leading, spacing: DLSpace.sm) {
                        WalkthroughStep(number: 3, title: "Hear the 3 safety words back", systemImage: "checkmark.shield.fill")
                        SafetyWordsCard(words: safetyWords,
                                        caption: "Not a password. Once your friend has joined, ask them to read their 3 safety words to you. They must match these.")
                    }
                }
                .padding(DLSpace.lg)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A numbered step heading in the new-group walkthrough: "1  Send the picture".
struct WalkthroughStep: View {
    let number: Int
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DLSpace.sm) {
            SlotNumber(number: number)
            Label(title, systemImage: systemImage)
                .font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The three safety words, styled apart from the Picture Password: they are not a secret to say first,
/// they are a check read back afterwards, proving both phones hold the same group phrase.
struct SafetyWordsCard: View {
    let words: [String]
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            Label("3 safety words", systemImage: "checkmark.shield.fill")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo)
            HStack(spacing: DLSpace.xs) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    Text(word).font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.dlNight, in: RoundedRectangle.key)
                }
            }
            Text(caption).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DLSpace.md)
        .background(Color.dlPanel, in: RoundedRectangle.key)
        .overlay { RoundedRectangle.key.stroke(Color.dlGo.opacity(0.6), lineWidth: 1.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safety words: \(words.joined(separator: ", ")). \(caption)")
        .accessibilityIdentifier("safety-words")
    }
}
