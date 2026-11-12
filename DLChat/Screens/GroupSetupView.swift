import DLCore
import ImageIO
import PhotosUI
import SwiftUI

/// Create a group or join one. Create opens straight on the Picture Password walkthrough (send the
/// picture, say the password, hear the 3 safety words back); the QR code and the full phrase wait
/// behind "Share group via QR". Nothing is saved until the person taps Save, so backing out leaves no trace.
struct GroupSetupView: View {
    let model: GroupModel
    /// Set when an invite link opened this screen: Join, with the phrase filled in and already checked.
    let invite: GroupInvite?
    let done: () -> Void

    @State private var joining = false
    @State private var wordCount = 15
    @State private var name = ""
    @State private var typed = ""
    @State private var prepared: PreparedGroup?
    @State private var working = false
    @State private var scanning = false
    @State private var problem: String?
    @FocusState private var focused: Bool
    @FocusState private var phraseFocused: Bool
    @State private var sharingQR = false
    @State private var confirmingClose = false
    /// The phrase being reviewed came out of a picture invite, so the joiner reads the safety words back.
    @State private var fromPicture = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var lockedPicture: [UInt8]?
    @State private var pictureSlots = PicturePasswordSlots()
    @FocusState private var focusedSlot: Int?

    /// An invite arrives already checked (`checked`), so the screen opens on its result. Checking after it
    /// appeared lost the result when SwiftUI rebuilt the sheet during the link hand-off.
    /// `joinFirst` opens on Join (first run, "I have an invite").
    init(model: GroupModel, invite: GroupInvite? = nil, checked: Result<PreparedGroup, JoinProblem>? = nil,
         joinFirst: Bool = false, done: @escaping () -> Void) {
        self.model = model
        self.invite = invite
        self.done = done
        _joining = State(initialValue: invite != nil || joinFirst)
        _typed = State(initialValue: invite?.phrase ?? "")
        _name = State(initialValue: invite?.name ?? "")
        switch checked {
        case .success(let ok): _prepared = State(initialValue: ok)
        case .failure(let found): _problem = State(initialValue: found.message)
        case nil: break
        }
    }

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(joining ? "Join a group" : "New group").font(.dl(.largeTitle, .bold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Close") {
                            Haptics.tap()
                            // A friend may already have joined from the picture: closing would lose the group here.
                            if !joining && prepared != nil { confirmingClose = true } else { done() }
                        }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                    }
                    if prepared == nil || !joining {
                        ModeSwitch(mode: Binding(get: { joining ? 1 : 0 }, set: { switchMode(join: $0 == 1) }), labels: ["Create", "Join"])
                    }
                    if let prepared {
                        if joining { review(prepared) } else { createWalkthrough(prepared) }
                    } else if joining && lockedPicture != nil {
                        pictureUnlock
                    } else if joining {
                        joinForm
                    } else {
                        makingPhrase
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .padding(DLSpace.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .fullScreenCover(isPresented: $scanning) {
            QRScanView(title: "Scan the phrase", rejected: "That code is not a group phrase.",
                       onFound: { found in
                           guard let phrase = GroupInvite.phrase(fromCode: found), GroupSetupView.looksLikePhrase(phrase) else { return false }
                           typed = phrase
                           join()
                           return true
                       }) { scanning = false }
        }
        .sheet(isPresented: $sharingQR) { qrShare }
        .confirmationDialog("Close without saving this group?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close without saving", role: .destructive) { done() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Anyone who already opened your picture would be in a group this phone does not have.")
        }
        .onChange(of: pickedPhoto) { _, item in if let item { openPicture(item) } }
        .task { await openDemoPicture() }
        // Create needs no choices first: the phrase is made as soon as Create shows (15 words; the
        // length can be changed under Share group via QR). A failure waits for Try again.
        .task(id: needsPhrase) { if needsPhrase { generate() } }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    // MARK: Forms

    private var needsPhrase: Bool { !joining && prepared == nil && !working && problem == nil }

    /// Create, while the phrase is being made (or after making it failed).
    private var makingPhrase: some View {
        VStack(alignment: .leading, spacing: 18) {
            if problem == nil {
                HStack(spacing: DLSpace.sm) {
                    ProgressView().tint(Color.dlSoft)
                    Text("Making your group…").font(.dl(.body)).foregroundStyle(Color.dlSoft)
                }
                .frame(maxWidth: .infinity, minHeight: DLSize.primary)
            } else {
                Button("Try again") { problem = nil }.buttonStyle(.dlPrimary)
            }
        }
    }

    /// Create: the picture and its password first, then the safety-word check, then Save. The QR code
    /// and the 10/15/20 words sit behind Share group via QR, for someone standing next to you.
    private func createWalkthrough(_ prepared: PreparedGroup) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("With each friend: send the picture, say your Picture Password out loud, then hear the 3 safety words back.")
                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
            TextField("Group name (optional)", text: $name)
                .focused($focused).submitLabel(.done)
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .dlField(focused: focused) { focused = true }
                .accessibilityHint("Shown to friends when they open the picture")
            PictureInviteSteps(phrase: prepared.phrase, name: name)
            VStack(alignment: .leading, spacing: DLSpace.sm) {
                WalkthroughStep(number: 3, title: "Hear the 3 safety words back", systemImage: "checkmark.shield.fill")
                SafetyWordsCard(words: prepared.safetyWords,
                                caption: "Not a password. Once your friend has joined, ask them to read their 3 safety words to you. They must match these. If one differs, do not use the group: tap Start over and send a new picture.")
            }
            Button("Save group") { save(prepared) }.buttonStyle(.dlPrimary)
            VStack(alignment: .leading, spacing: DLSpace.xs) {
                Button("Share group via QR") { focused = false; sharingQR = true }
                    .buttonStyle(.dlSecondary).accessibilityIdentifier("share-qr")
                Text("For someone right next to you: a QR code and the full \(prepared.phrase.indices.count)-word phrase.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
            Button("Start over") { startOver() }.buttonStyle(.dlSecondary)
        }
    }

    /// Behind Share group via QR: the phrase as a QR code and as words, and its length.
    private var qrShare: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Share group via QR").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Done") { Haptics.tap(); sharingQR = false }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                            .accessibilityIdentifier("qr-done")
                    }
                    if let prepared {
                        Text("For someone right next to you. Let them scan the code, or read the words in person, never over the radio or in a message. Then check the 3 safety words together.")
                            .font(.dl(.body)).foregroundStyle(Color.dlSoft)
                        invitePanel(GroupInvite(phrase: prepared.phrase.text, name: name))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DLSpace.xs), count: 3), spacing: DLSpace.xs) {
                            ForEach(Array(prepared.phrase.words.enumerated()), id: \.offset) { n, w in
                                VStack(spacing: 2) {
                                    Text("\(n + 1)").font(.caption2).foregroundStyle(Color.dlSoft).monospacedDigit()
                                    Text(w).font(.dl(.headline, .bold)).foregroundStyle(Color.dlText).minimumScaleFactor(0.7).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(Color.dlPanel, in: RoundedRectangle.key)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("phrase-words")
                        Text("Phrase length").font(.dl(.headline)).foregroundStyle(Color.dlText)
                        ModeSwitch(
                            mode: Binding(get: { [10, 15, 20].firstIndex(of: wordCount) ?? 1 },
                                          set: { let next = [10, 15, 20][$0]; if next != wordCount { wordCount = next; generate() } }),
                            labels: ["10 words", "15 words", "20 words"])
                            .disabled(working)
                        Text("Changing the length makes a new phrase, so a new picture and new safety words too. Do it before you share anything.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                    }
                }
                .padding(DLSpace.lg)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Type the words in order, with a space between each. Capital letters do not matter.")
                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
            TextField("Group name (optional)", text: $name)
                .focused($focused).submitLabel(.next)
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .onSubmit { phraseFocused = true }
                .dlField(focused: focused) { focused = true }
            TextField("The phrase", text: $typed, axis: .vertical)
                .focused($phraseFocused).submitLabel(.done)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable).textContentType(.none)
                .dlField(focused: phraseFocused, minHeight: 140) { phraseFocused = true }
                .accessibilityIdentifier("join-phrase")
            Button(working ? "Checking…" : "Check the phrase") { join() }
                .buttonStyle(.dlPrimary).disabled(working || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Scan the phrase QR code") { focused = false; phraseFocused = false; scanning = true }
                .buttonStyle(.dlSecondary).disabled(working).accessibilityIdentifier("scan-phrase")
            PhotosPicker(selection: $pickedPhoto, matching: .images) { Text("Open a picture invite") }
                .buttonStyle(.dlSecondary).disabled(working).accessibilityIdentifier("open-picture")
        }
    }

    /// After a picture invite is picked: only the password, so it cannot end up below the fold. One
    /// numbered box per word, matching the numbers on the sender's screen.
    private var pictureUnlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Picture invite found. Type the Picture Password your friend said out loud, word 1 in box 1.")
                .font(.dl(.body)).foregroundStyle(Color.dlText)
            // The friend says how many; the picture does not.
            DLSegments(selection: Binding(get: { pictureSlots.count }, set: { pictureSlots.resize(to: $0) }),
                       options: Array(PictureInvite.passwordWordCounts)) { "\($0) words" }
            .accessibilityIdentifier("picture-password-length")
            ForEach(0..<pictureSlots.count, id: \.self) { index in
                passwordSlot(index)
            }
            Button(working ? "Unlocking…" : "Unlock the picture", action: unlockPicture)
                .buttonStyle(.dlPrimary)
                .disabled(working || pictureSlots.isEmpty)
            Button("Use a different way") { lockedPicture = nil; pictureSlots = PicturePasswordSlots(); problem = nil }
                .buttonStyle(.dlSecondary)
        }
        .onAppear { focusedSlot = 0 }
    }

    /// Box `index` (shown as index + 1). A space or a pasted run of words moves on to the next boxes.
    private func passwordSlot(_ index: Int) -> some View {
        let isLast = index == pictureSlots.count - 1
        return HStack(spacing: DLSpace.sm) {
            SlotNumber(number: index + 1)
            TextField("Word \(index + 1)", text: Binding(
                get: { pictureSlots.words.indices.contains(index) ? pictureSlots.words[index] : "" },
                set: { text in if let next = pictureSlots.enter(text, at: index), next != index { focusedSlot = next } }))
                .focused($focusedSlot, equals: index)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                .textContentType(.none)
                .submitLabel(isLast ? .go : .next)
                .onSubmit { if isLast { unlockPicture() } else { focusedSlot = index + 1 } }
                .dlField(focused: focusedSlot == index) { focusedSlot = index }
                .accessibilityLabel("Word \(index + 1) of \(pictureSlots.count)")
                .accessibilityIdentifier("picture-password-slot-\(index + 1)")
        }
    }

    /// Join: the phrase checked, and the 3 safety words to compare before joining.
    private func review(_ prepared: PreparedGroup) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(invite != nil ? "This came from a link, which anyone can make. Join only if the person you expect reads you these same three safety words aloud."
                 : fromPicture ? "Picture unlocked. Last step: read these 3 safety words to your friend. Join only if they say theirs match."
                 : "Phrase accepted. Check the safety words below match the other phones.")
                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
            SafetyWordsCard(words: prepared.safetyWords,
                            caption: "Everyone in the group sees these same three. If one differs, the phrase was entered wrong or this is not your friend's group.")
            Button("Join group") { save(prepared) }.buttonStyle(.dlPrimary)
            Button("Start over") { startOver() }.buttonStyle(.dlSecondary)
        }
    }

    /// The invite as a QR code (scannable by the iPhone Camera or DLChat's Join). No plain link to send:
    /// it would leave the phrase in chat history and backups. The picture invite is the way to send one.
    private func invitePanel(_ invite: GroupInvite) -> some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            QRCodeBox(text: invite.url.absoluteString, label: "QR code holding the group invite")
                .accessibilityIdentifier("phrase-qr")
            Text("Others scan this with the iPhone Camera, or in DLChat under Join.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    /// A phrase code is the group's words separated by spaces. Message codes and other codes are not.
    static func looksLikePhrase(_ text: String) -> Bool {
        Phrase.lengths.contains(text.split(whereSeparator: \.isWhitespace).count)
    }

    // MARK: Actions

    private func generate() {
        working = true; problem = nil
        let count = wordCount
        Task {
            defer { working = false }
            do {
                let made = try await model.prepareNew(words: count)
                // Join may have been picked (or a picture opened) while the phrase was being made.
                if !joining && count == wordCount { prepared = made }
            } catch {
                if !joining { problem = "Could not make a random phrase. Try again." }
            }
        }
    }

    private func switchMode(join: Bool) {
        guard join != joining else { return }
        joining = join; problem = nil; prepared = nil; fromPicture = false; sharingQR = false
    }

    /// Back to the start: Join goes back to its form, Create makes a new phrase (and picture).
    private func startOver() {
        prepared = nil; problem = nil; fromPicture = false; sharingQR = false
    }

    private func join() {
        focused = false; phraseFocused = false; working = true; problem = nil
        Task {
            defer { working = false }
            let result = await model.prepareJoin(typed)
            // Create may have been picked while the phrase was checked.
            guard joining else { return }
            switch result {
            case .success(let ok): prepared = ok
            case .failure(let found): problem = found.message
            }
        }
    }

    /// Reads the frame of a picked photo; the password is asked for next.
    private func openPicture(_ item: PhotosPickerItem) {
        problem = nil; fromPicture = false; lockedPicture = nil; pictureSlots = PicturePasswordSlots()
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            pickedPhoto = nil
            let payload = await Task.detached { () -> [UInt8]? in
                guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                return PictureInvite.read(image)
            }.value
            if let payload { lockedPicture = payload }
            else { problem = "That picture is not a DLChat invite, or it was cropped. Use the whole picture, or a screenshot that shows all of it, and try again." }
        }
    }

    /// UI tests only (`-seed-demo -demo-picture-invite`): Join opens on a throwaway picture invite whose
    /// password is `demoPicturePassword`, since a test cannot pick a photo from the library.
    static let demoPicturePassword = "maple river stone owl badge"
    private func openDemoPicture() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seed-demo"), arguments.contains("-demo-picture-invite"), invite == nil else { return }
        let password = Self.demoPicturePassword
        let payload = await Task.detached { () -> [UInt8]? in
            guard let phrase = try? Phrase.generate(words: 10),
                  let image = try? PictureInvite.render(phrase: phrase, name: "Porch", password: password)
            else { return nil }
            return PictureInvite.read(image)
        }.value
        guard let payload else { return }
        joining = true; prepared = nil; lockedPicture = payload
    }

    private func unlockPicture() {
        // Any entry can be tried, so the screen never hints how many words the password has.
        guard let payload = lockedPicture, !pictureSlots.isEmpty else { return }
        focusedSlot = nil
        let password = pictureSlots.password
        working = true; problem = nil
        Task {
            let result = await Task.detached { Result { try PictureInvite.unlock(payload, password: password) } }.value
            working = false
            switch result {
            case .success(let opened):
                typed = opened.phrase.text
                if name.trimmingCharacters(in: .whitespaces).isEmpty { name = opened.name }
                lockedPicture = nil; pictureSlots = PicturePasswordSlots()
                fromPicture = true
                join()
            case .failure(PictureInvite.UnlockError.wrongPassword):
                problem = "Those words do not open this picture. Check each word and its number with your friend."
            case .failure:
                problem = "This picture is damaged. Ask your friend to send it again."
            }
        }
    }

    private func save(_ prepared: PreparedGroup) {
        do {
            try model.save(name: name, prepared: prepared)
            Haptics.success()
            done()
        } catch let found as JoinProblem {
            problem = found.message
        } catch {
            problem = "Could not save the group on this phone."
        }
    }
}
