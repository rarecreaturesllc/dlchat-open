import DLCore
import SwiftUI

/// Receive: paste the encrypted words at the top and Decrypt; or Decrypt Word by Word, with suggestions and
/// the words typed so far. A decrypted message fills the page until Acknowledged or Clear.
struct ReceiveView: View {
    let decode: DecodeModel
    let groups: GroupModel
    let radioGate: (@escaping () -> Void) -> Void
    /// Acknowledged: posts "Decrypted" in the given group and room's chat and opens Chat. Returns the problem to show, or nil once sent.
    var acknowledge: ((UUID, String) -> String?)?
    @FocusState private var focused: Bool
    @State private var ackProblem: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanning = Launch().screen == .scan
    @State private var listening = Launch().screen == .listen
    @State private var openingSound = false
    @State private var soundNote: String?
    /// Encrypted words pasted from Chat or another app, opened with Decrypt.
    @State private var pasted = ""
    @FocusState private var pasteFocused: Bool
    /// Plays an encrypted sound tapped in Chat; the message opens when it finishes.
    @State private var soundPlayer = TonePlayer()
    @Environment(\.scenePhase) private var scenePhase

    /// A message is open: the page shows it, Acknowledged and Clear, and nothing else.
    private var showingMessage: Bool {
        if case .message = decode.outcome { return true }
        return false
    }

    /// Words are being put in one at a time (Decrypt Word by Word), or pasted words did not open on their own.
    private var enteringWords: Bool { decode.wordByWord || !decode.entered.isEmpty }

    var body: some View {
        // As on Send: a compact paste box with the deck straight under it.
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: DLSpace.md) {
                if !decode.hasGroup {
                    result
                } else if showingMessage {
                    result
                    clearButton
                } else if let sound = decode.pendingSound {
                    soundFromChat(sound)
                } else if enteringWords {
                    wordByWord
                } else {
                    pasteFirst
                }
            }
            .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.xs)
            .frame(minHeight: geo.size.height, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: soundPlayer.state) { _, state in
            guard let sound = decode.pendingSound else { return }
            switch state {
            case .finished: openSound(sound, note: nil)
            // The speaker could not play it: open it all the same, and say why there was no sound.
            case .failed(let why): openSound(sound, note: "No sound played (\(why)), but the message was decrypted.")
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { soundPlayer.stop() } }
        .onDisappear { soundPlayer.stop() }
        .onChange(of: decode.outcome) { ackProblem = nil }
        .fileImporter(isPresented: $openingSound, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            guard let bursts = SoundFile.bursts(in: url) else { soundNote = "DLChat cannot read that sound file."; return }
            soundNote = bursts.contains(where: { decode.readHeard($0) }) ? nil
                : (bursts.isEmpty ? "No message tones found in that sound. If it was sent as a voice message, ask for it as a file."
                                  : "That sound holds a message that is not for your groups.")
        }
        .fullScreenCover(isPresented: $scanning) {
            QRScanView(title: "Scan a message", rejected: "That code is not a message for your groups.",
                       onFound: { decode.readScanned($0) }) { scanning = false }
        }
        .fullScreenCover(isPresented: $listening) {
            ToneListenView(onHeard: { decode.readHeard($0) }) { listening = false }
        }
    }

    /// The usual page: paste the encrypted words at the top and Decrypt, like typing a message on Send.
    @ViewBuilder private var pasteFirst: some View {
        // Encrypted words copied out of Chat or another app (Send > Encrypt Words on the other phone).
        TextField("Paste encrypted words", text: $pasted, axis: .vertical)
            .focused($pasteFocused)
            // The same compact box as Send: four lines; more words scroll inside.
            .lineLimit(4, reservesSpace: true)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .dlField(focused: pasteFocused) { pasteFocused = true }
            .accessibilityIdentifier("paste-field")
        if let soundNote {
            Label(soundNote, systemImage: "exclamationmark.triangle").font(.dl(.subheadline)).foregroundStyle(Color.dlWarn)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The deck, as on Send: the other ways in as keys, then the one green bar.
        // Words read out on a call or over a radio: put them in one at a time.
        Button("Decrypt word by word") { pasteFocused = false; pasted = ""; decode.wordByWord = true; focused = true }
            .buttonStyle(.dlSecondary).accessibilityIdentifier("decrypt-word-by-word")
        KeyRow {
            Button { radioGate { listening = true } } label: { KeyLabel(title: "Listen", icon: "ear") }.accessibilityIdentifier("listen")
            Button { scanning = true } label: { KeyLabel(title: "Scan QR", icon: "qrcode.viewfinder") }.accessibilityIdentifier("scan-qr")
            Button { openingSound = true } label: { KeyLabel(title: "Open a sound file", icon: "folder") }.accessibilityIdentifier("open-sound")
        }
        .buttonStyle(DLKeyStyle())
        Button("Decrypt") {
            pasteFocused = false
            decode.paste(pasted)
            pasted = ""
        }
        .buttonStyle(.dlPrimary)
        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("paste-decrypt")
    }

    /// Decrypt Word by Word: how far along it is, a field for the next word, and the words so far.
    @ViewBuilder private var wordByWord: some View {
        result
        // Short placeholder: a one-line field must not clip at the largest text sizes.
        TextField("Next word", text: Bindable(decode).typed)
            .focused($focused).submitLabel(.next)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .onChange(of: decode.typed) { decode.ingestTyped() }
            .onSubmit { decode.submit(); focused = true }
            .dlField(focused: focused) { focused = true }
            .accessibilityIdentifier("word-field")
        if !decode.suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DLSpace.xs) {
                    ForEach(decode.suggestions, id: \.self) { s in
                        Button { Haptics.tap(); decode.add(s); focused = true } label: {
                            Text(s).font(.dl(.headline)).foregroundStyle(Color.dlText)
                                .padding(.horizontal, DLSpace.md).frame(minHeight: DLSize.control)
                                .background(Color.dlPanel, in: RoundedRectangle.key)
                        }
                        .buttonStyle(.dlPress)
                    }
                }
            }
        }
        ButtonPair {
            Button("Missed one") { decode.addMissing() }.buttonStyle(.dlSecondary).accessibilityLabel("Missed a word")
        } second: {
            Button("Undo") { decode.undo() }.buttonStyle(.dlSecondary).disabled(decode.entered.isEmpty)
        }
        if decode.canRepair {
            Button("Try to repair") { focused = false; decode.repair() }.buttonStyle(.dlSecondary)
        }
        if !decode.entered.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DLSpace.xs)], spacing: DLSpace.xs) {
                // Each chip carries its own word. Looking it up by index (`entered[i]`) crashed when
                // Undo emptied the list: the grid could still ask for a chip whose index was gone.
                ForEach(Array(decode.entered.enumerated()), id: \.offset) { _, word in
                    WordChip(word: word, missing: word == Repair.missingMarker || WordList.index(of: word) == nil)
                }
            }
            .accessibilityElement(children: .contain)
        }
        clearButton
    }

    /// Clear: forgets the words and the message on screen and puts the page back to paste-first.
    private var clearButton: some View {
        Button("Clear") {
            focused = false
            pasteFocused = false
            soundPlayer.stop()
            pasted = ""
            soundNote = nil
            ackProblem = nil
            decode.clear()
        }
        .buttonStyle(.dlSecondary).accessibilityIdentifier("receive-clear")
    }

    /// An encrypted sound tapped in Chat: Decrypt Sound plays it, then the message shows above.
    @ViewBuilder private func soundFromChat(_ sound: Data) -> some View {
        let busy = soundPlayer.state == .playing || soundPlayer.state == .starting
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            Label("Encrypted sound from Chat", systemImage: "waveform").font(.dl(.headline)).foregroundStyle(Color.dlText)
            Text(busy ? "Playing. The message appears when the sound ends."
                      : "About \(Int(Modem.duration(bytes: sound.count).rounded(.up))) seconds. Tap Decrypt Sound to hear it, then read it.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
            if busy { ProgressView(value: soundPlayer.progress).progressViewStyle(DLMeterStyle()).accessibilityLabel("Playback progress") }
            Button(busy ? "Playing…" : "Decrypt Sound") { soundPlayer.play(Modem.encode([UInt8](sound)), volume: Self.decryptSoundVolume) }
                .buttonStyle(.dlPrimary).disabled(busy).accessibilityIdentifier("decrypt-sound")
            // Silences it, before or while it plays; it still finishes and the message still opens.
            Button { soundPlayer.muted.toggle() } label: {
                Label(soundPlayer.muted ? "Unmute" : "Mute", systemImage: soundPlayer.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.dlSecondary).accessibilityIdentifier("decrypt-sound-mute")
            .accessibilityValue(soundPlayer.muted ? "Muted" : "On")
            Button("Not now") { Haptics.tap(); soundPlayer.stop(); decode.pendingSound = nil }
                .font(.dl(.headline)).foregroundStyle(Color.dlSoft).frame(minHeight: DLSize.control)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dlPanel, in: RoundedRectangle.key)
    }

    /// Decrypt Sound plays a quarter quieter than Send's full-level tones (it is for this phone's ears, not a radio).
    static let decryptSoundVolume: Float = 0.75

    private func openSound(_ sound: Data, note: String?) {
        decode.pendingSound = nil
        soundNote = decode.readHeard(sound) ? note : "That sound holds a message that is not for your groups."
    }

    @ViewBuilder private var result: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            if !decode.hasGroup {
                Text("No group yet").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                Text("Create or join a group first, in Chat. Only its members can read a message.")
                    .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
            } else {
                switch decode.outcome {
                case .message(let message, let groupName):
                    messageCard(message, groupName: groupName)
                case .repairing:
                    Text("Trying to repair").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                    Text("Testing one changed word at a time.").font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                case .notRead:
                    Text("Could not decrypt").font(.dl(.title2, .bold)).foregroundStyle(Color.dlWarn)
                    Text("No single changed word makes it readable. Check the words against what was said, add ? for any missed word, or ask for it again. It may be for another group.")
                        .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                case .typing:
                    typing
                }
            }
        }
        .padding(focused ? DLSpace.sm : 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dlPanel, in: RoundedRectangle.key)
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : DLMotion.move, value: resultKind)
        // A haptic when a message opens or cannot be read, so the result is felt as well as seen.
        .sensoryFeedback(trigger: resultKind) { _, new in new == 1 ? .success : new == 2 ? .error : nil }
    }

    /// 0 typing or repairing, 1 a message, 2 could not decrypt.
    private var resultKind: Int {
        switch decode.outcome {
        case .message: return 1
        case .notRead: return 2
        default: return 0
        }
    }

    @ViewBuilder private var typing: some View {
        let count = decode.entered.count
        if focused {
            Text("\(count) words so far").font(.dl(.headline)).foregroundStyle(Color.dlSoft)
        } else {
            Text("\(count) words so far").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
            if decode.gaps > 1 {
                Text("\(decode.gaps) words are missing or not on the list. Only one can be repaired: fix the others first.")
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
            } else {
                Text("Keep typing. The message appears when it can be read.")
                    .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
            }
        }
    }

    @ViewBuilder private func messageCard(_ message: ReadMessage, groupName: String?) -> some View {
        Text(message.text).font(.dl(.title, .bold)).foregroundStyle(Color.dlText)
            .accessibilityIdentifier("decoded-text")
        // The only action: Acknowledged posts "Decrypted" in Chat (never the words) and opens Chat.
        // Not acknowledged, nothing is posted. The decrypted text is never copied or put in Chat.
        // Once per message: decrypting it again shows it again, but "Decrypted" is not posted a second time.
        if decode.alreadyAcknowledged {
            Label("Already acknowledged. Decrypted is posted in Chat once.", systemImage: "lock.open")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("already-acknowledged")
        } else if let acknowledge, let target = decode.replyTarget(for: message) {
            if let ackProblem {
                Label(ackProblem, systemImage: "exclamationmark.triangle").font(.dl(.subheadline)).foregroundStyle(Color.dlWarn)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("acknowledge-problem")
            }
            Button("Acknowledged") {
                ackProblem = acknowledge(target.groupID, target.room)
                if ackProblem == nil { decode.markAcknowledged(message); decode.clear() } else { Haptics.warn() }
            }
            .buttonStyle(.dlPrimary).accessibilityIdentifier("acknowledge")
            .accessibilityHint("Posts Decrypted in Chat, without the message, and opens Chat")
        }
        if let repair = message.repair {
            Label(repairNote(repair), systemImage: "wrench.and.screwdriver")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo)
        } else {
            Label("Verified", systemImage: "checkmark.seal")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo)
        }
        if let first = decode.heardBefore {
            Label("Already received \(first.formatted(date: .abbreviated, time: .shortened)). This may be the same message sent again.", systemImage: "arrow.triangle.2.circlepath")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                .accessibilityIdentifier("already-received")
        }
        if message.readOnce {
            Label("Read once: the sender asked that this not be kept. Nothing of it is saved on this phone.", systemImage: "eye.slash")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                .accessibilityIdentifier("read-once-note")
        }
        if message.duress {
            Label("The sender marked this as sent under pressure. Treat it with care.", systemImage: "exclamationmark.triangle")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
        }
        switch Receiver.timeNote(sentAt: message.sentAt) {
        case .normal:
            Text("Sent \(Self.relative(message.sentAt))").font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
        case .clockMayDiffer:
            Label("Sent \(message.sentAt.formatted(date: .abbreviated, time: .shortened)), which is ahead of this phone's clock. One clock may be wrong.", systemImage: "clock.badge.exclamationmark")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
        case .old:
            Label("Sent \(message.sentAt.formatted(date: .abbreviated, time: .shortened)). This is an old message, possibly sent again.", systemImage: "clock.arrow.circlepath")
                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
        }
        if let groupName {
            Text("From group \(groupName)").font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
        }
    }

    private func repairNote(_ repair: Repaired) -> String {
        let place = "word \(repair.position + 1)"
        if repair.wasMissing {
            return "Repaired: filled in \(place) with \"\(repair.replacement)\""
        }
        return "Repaired: \(place) was \"\(repair.heard ?? "")\", now \"\(repair.replacement)\""
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
