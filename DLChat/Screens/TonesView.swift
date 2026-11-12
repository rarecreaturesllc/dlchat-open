import SwiftUI

/// Plays the message as sound for a phone nearby to hear. Wipe stays one shield tap away.
struct TonePlayView: View {
    let samples: [Float]
    let lock: AppLock
    let wipe: () -> Bool
    /// Send > Encrypt Sound: also offers to post the sound in a chosen chat.
    var chat: ToneChat?
    let done: () -> Void
    @State private var player = TonePlayer()
    @State private var target: ChatTarget?
    @State private var safety = false
    @State private var soundFile: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.md) {
                HStack {
                    Text("Encrypt Sound").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    SafetyButton { safety = true }
                    Button("Close") { Haptics.tap(); player.stop(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("tones-close")
                }
                // Play, Send in the chat and Share as a sound file sit together at the bottom of the same scroll.
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DLSpace.md) {
                            let seconds = Int(TonePlayer.duration(of: samples).rounded(.up))
                            Readout(value: String(format: "%02d", seconds), legend: "seconds of sound", detail: "approximate")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("About \(seconds) seconds of sound").accessibilityIdentifier("tones-length")
                            Text("Hold this phone's speaker close to the other phone's microphone, set the volume to about three quarters, then tap Play.")
                                .font(.dl(.body)).foregroundStyle(Color.dlSoft)
                            ProgressView(value: player.progress).progressViewStyle(DLMeterStyle()).accessibilityLabel("Playback progress")
                            status
                            ForEach(player.warnings, id: \.self) { RouteWarning(text: $0) }
                            Text("Only phones in this group can read it. Anyone nearby can hear the sound, but it cannot be decoded without the phrase.")
                                .font(.footnote).foregroundStyle(Color.dlSoft)
                            Spacer(minLength: DLSpace.md)
                            if let chat, let bound = Binding($target) {
                                PostToChatSection(groups: chat.groups, target: bound, what: "this sound") {
                                    chat.post(bound.wrappedValue)
                                } before: {
                                    playButton
                                } after: {
                                    shareButton
                                }
                            } else {
                                playButton
                                shareButton
                            }
                        }
                        .frame(minHeight: geo.size.height)
                    }
                }
            }
            .padding(DLSpace.md)
        }
        .sheet(isPresented: $safety) { SafetyView(lock: lock, wipe: { player.stop(); let ok = wipe(); if ok { done() }; return ok }) { safety = false } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onAppear { soundFile = SoundFile.write(samples); target = chat?.start }
        .onDisappear {
            player.stop()
            if let soundFile { try? FileManager.default.removeItem(at: soundFile) }
        }
    }

    private var playButton: some View {
        let busy = player.state == .playing || player.state == .starting
        return Button(busy ? "Stop" : player.state == .finished ? "Play again" : "Play") {
            if busy { player.stop() } else { player.play(samples) }
        }
        .buttonStyle(.dlPrimary).accessibilityIdentifier("tones-play")
    }

    @ViewBuilder private var shareButton: some View {
        if let file = soundFile {
            ShareLink(item: file, preview: SharePreview("DLChat message")) {
                Label("Share as a sound file", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: DLSize.control)
            }
            .buttonStyle(.dlSecondary)
            .accessibilityIdentifier("tones-share")
            Text("The other person saves it to Files, then opens it in Receive > Open a sound file. Send it as a file, not a voice message: voice messages are squeezed and may not decode.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var status: some View {
        switch player.state {
        case .idle: EmptyView()
        case .starting: Text("Starting the speaker").font(.dl(.headline)).foregroundStyle(Color.dlSoft)
        case .playing: Text("Playing").font(.dl(.headline)).foregroundStyle(Color.dlGo)
        case .finished: Text("Done. Say \"over\" or send it again.").font(.dl(.headline)).foregroundStyle(Color.dlGo)
        case .failed(let note): RouteWarning(text: note)
        }
    }
}

/// Encrypt Sound's chats: where it can be posted, which one first, and how to post it.
struct ToneChat {
    let groups: [ChatGroup]
    let start: ChatTarget
    /// Returns the problem to show, or nil once it is on its way.
    let post: (ChatTarget) -> String?
}

/// Listens for a tone burst from a phone speaker nearby. Foreground only: it stops when the app is not on screen.
struct ToneListenView: View {
    let onHeard: (Data) -> Bool
    let done: () -> Void
    @State private var listener = ToneListener()
    @State private var note: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.md) {
                HStack {
                    Text("Listen for sound").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Close") { Haptics.tap(); listener.stop(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("listen-close")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSpace.md) {
                        statusBlock
                        ForEach(listener.warnings, id: \.self) { RouteWarning(text: $0) }
                        if let note { RouteWarning(text: note) }
                        Text("Hold this phone's microphone near the other phone's speaker. The message appears when a whole burst has been heard. The microphone only listens for tones. Nothing it hears is saved or sent.")
                            .font(.footnote).foregroundStyle(Color.dlSoft)
                    }
                }
                Button(listener.state == .listening ? "Stop listening" : "Listen again") {
                    if listener.state == .listening { listener.stop() } else { Task { await listener.start() } }
                }
                .buttonStyle(.dlSecondary).accessibilityIdentifier("listen-toggle")
            }
            .padding(DLSpace.md)
        }
        .preferredColorScheme(.dark)
        .task {
            listener.onBurst = { data in
                if onHeard(data) {
                    Haptics.success()
                    listener.stop()
                    done()
                } else {
                    note = "Heard a message that is not for your groups. Still listening."
                }
            }
            await listener.start()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { listener.stop() } }
        .onDisappear { listener.stop() }
    }

    @ViewBuilder private var statusBlock: some View {
        switch listener.state {
        case .idle:
            Text("Not listening").font(.dl(.title, .bold)).foregroundStyle(Color.dlText)
        case .listening:
            Text("Listening").font(.dl(.title, .bold)).foregroundStyle(Color.dlGo).accessibilityIdentifier("listen-status")
            ProgressView(value: listener.level).progressViewStyle(DLMeterStyle())
                .accessibilityLabel("Sound level").accessibilityValue("\(Int(listener.level * 100)) percent")
        case .denied:
            Text("The microphone is off for DLChat").font(.dl(.title, .bold)).foregroundStyle(Color.dlText)
            Text("Turn it on in the Settings app, or use the words instead.").font(.dl(.body)).foregroundStyle(Color.dlSoft)
                .accessibilityIdentifier("listen-problem")
        case .failed(let problem):
            Text("Cannot listen").font(.dl(.title, .bold)).foregroundStyle(Color.dlWarn)
            Text(problem).font(.dl(.body)).foregroundStyle(Color.dlSoft).accessibilityIdentifier("listen-problem")
        }
    }
}

private struct RouteWarning: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
