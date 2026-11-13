import DLCore
import SwiftUI
import UIKit

/// A plain Meshtastic chat, opened from the Chat drawer (or Manage groups): one of the radio's
/// channels (the public one), or one radio directly. Talks with people on the stock Meshtastic app, so
/// nothing here is sealed with a DLChat phrase, and the screen says so before anything is typed.
struct MeshChatView: View {
    let mesh: MeshtasticModel
    let conversation: MeshConversation

    var body: some View {
        VStack(spacing: 0) {
            header
            privacyNote
            radioStatus
            conversationList
            MeshComposer(limit: Meshtastic.maxTextBytes) { mesh.sendText($0, in: conversation) }
        }
        .onAppear { mesh.setViewing(true) }
        .onDisappear { mesh.setViewing(false) }
    }

    private var title: String { mesh.title(of: conversation) }

    /// The way back is the "Chats" bar above (or the Chat tab), which also names the chat; this line says what kind it is.
    private var header: some View {
        Text(kindLine).dlCaps(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.xs)
            .accessibilityIdentifier("mesh-chat-kind")
    }

    private var kindLine: String {
        switch conversation {
        case .channel: return "Meshtastic channel"
        case .direct(let num):
            let short = mesh.nodes[num]?.shortName ?? ""
            return short.isEmpty ? "Meshtastic direct message" : "Direct message · \(short)"
        }
    }

    /// Always shown: what protects this chat, and what it does not.
    private var privacyNote: some View {
        let (icon, color, text) = privacy
        return Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon) }
            .font(.dl(.footnote)).foregroundStyle(color)
            .padding(DLSpace.sm).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay { RoundedRectangle.key.stroke(color.opacity(0.5), lineWidth: 1) }
            .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.xs)
            .accessibilityIdentifier("mesh-privacy")
    }

    private var privacy: (String, Color, String) {
        switch conversation {
        case .channel(let index):
            let ch = mesh.channel(index)
            var text = ch?.keyIsPublic ?? true
                ? "Not private. Anyone with a Meshtastic radio in range can read this channel, and radios that upload to the internet (MQTT) can post it online. Your DLChat phrase is not used here."
                : "Readable by everyone who has this channel's key, not only your group. Your DLChat phrase is not used here."
            if ch?.uplink == true { text += " Your radio uploads this channel to the internet." }
            return ("exclamationmark.triangle.fill", .dlWarn, text)
        case .direct(let num):
            if mesh.licensed {
                return ("exclamationmark.triangle.fill", .dlWarn, "Your radio is in licensed mode, which does not allow private messages. Nothing can be sent here.")
            }
            var text = "Encrypted by Meshtastic's own keys between the two radios, not by your DLChat phrase. Other radios can still see that your radio messaged this one, and when."
            if mesh.nodes[num]?.publicKey == nil { text += " This radio's key has not arrived yet, so a message may not go until it announces itself." }
            return ("lock.fill", .dlSoft, text)
        }
    }

    @ViewBuilder private var radioStatus: some View {
        // Licensed mode is explained above: channels still work in it, direct messages do not.
        if mesh.status != .ready || mesh.regionUnset || mesh.applying {
            Text(("Radio · " + MeshStatus.text(mesh)).uppercased()).dlCaps(.caption)
                .foregroundStyle(Color.dlSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.xs)
                .accessibilityIdentifier("mesh-radio-status")
        }
    }

    private var messages: [MeshText] { mesh.texts[conversation] ?? [] }

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        Text(conversation.isDirect ? "No messages with this radio yet."
                             : mesh.keep == .off ? "Nothing heard on this channel since DLChat opened. Messages here are not saved."
                                                 : "Nothing heard on this channel in the time you keep Meshtastic chats.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(DLSpace.md)
                    }
                    ForEach(messages) { bubble($0).id($0.id) }
                }
                .padding(.vertical, DLSpace.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("mesh-chat-scroll")
            .stayingAtNewest(proxy, conversation: conversation, newest: messages.last?.id)
        }
    }

    /// One line of the log, as in the group chat: time in the gutter, who in a tag, how it travelled in caps.
    private func bubble(_ m: MeshText) -> some View {
        let mine = m.outgoing
        let sender = mine ? nil : (conversation.isDirect ? nil : mesh.nodes[m.from]?.displayName ?? MeshNode(num: m.from, source: .radio).displayName)
        let failed: Bool = { if case .failed = m.state { true } else { false } }()
        let time = m.at.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(m.at) ? nil : m.at.formatted(.dateTime.month(.abbreviated).day())
        return LogRow(time: time, day: day, mine: mine) {
            if let sender { Text(sender).font(.dl(.caption, .semibold)).foregroundStyle(Color.dlSoft) }
            Text(m.text).font(.dl(.body)).foregroundStyle(Color.dlText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            let route = detail(m)
            if !route.isEmpty {
                Label {
                    Text(route.uppercased()).dlCaps(.caption)
                } icon: {
                    if failed { Image(systemName: "exclamationmark.triangle").font(.dl(.caption, .semibold)) }
                }
                .foregroundStyle(failed ? Color.dlWarn : Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !mine, conversation.isDirect, !m.isPrivate {
                Label("Sent with a channel key, not privately", systemImage: "exclamationmark.triangle")
                    .font(.dl(.caption, .semibold)).foregroundStyle(Color.dlWarn)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((mine ? "You: " : "\(sender ?? title): ") + m.text + ". " + (day.map { $0 + ", " } ?? "") + time + (detail(m).isEmpty ? "" : " · " + detail(m)))
    }

    /// How it travelled and what became of it; the time is in the log's gutter.
    private func detail(_ m: MeshText) -> String {
        var parts: [String] = []
        if let hops = m.hops { parts.append(hops == 0 ? "heard directly" : "\(hops) \(hops == 1 ? "hop" : "hops")") }
        switch m.state {
        case .received: break
        case .sending: parts.append("sending by radio")
        case .relayed: parts.append(conversation.isDirect ? "passed on by the mesh" : "repeated by another radio")
        case .delivered: parts.append("delivered")
        case .unheard: parts.append("sent · no radio heard repeating it")
        case .failed(let why): parts.append("not sent: \(why)")
        }
        return parts.joined(separator: " · ")
    }
}

/// The Meshtastic message box, with a byte count: Meshtastic limits text by bytes, not letters.
private struct MeshComposer: View {
    let limit: Int
    let onSend: (String) -> String?
    @State private var text = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    /// A new box after each send, and the sent text kept out of it: voice typing writes it back.
    @State private var field = 0
    @State private var echo = SentEcho()

    private var bytes: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.dl(.footnote)).foregroundStyle(Color.dlWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mesh-problem")
            }
            HStack(alignment: .bottom, spacing: DLSpace.xs) {
                TextField("Meshtastic message", text: $text, axis: .vertical)
                    .focused($focused)
                    .chatKeyboard()
                    .chatBox()
                    .padding(.leading, 12)
                    .accessibilityIdentifier("mesh-field")
                    // Focus moves to the new box once it is there, so the keyboard stays up for the next message.
                    .task(id: field) { if field > 0 { focused = true } }
                    .id(field)
                    .onChange(of: text) {
                        problem = nil
                        if echo.isEcho(text) { text = "" }
                    }
                if bytes > limit * 3 / 4 {
                    Text("\(bytes)/\(limit)").font(.dl(.caption, .semibold)).monospacedDigit()
                        .foregroundStyle(bytes > limit ? Color.dlWarn : Color.dlSoft)
                        .frame(minHeight: DLSize.control)
                        .accessibilityLabel("\(bytes) of \(limit) bytes")
                }
                Button(action: send) {  // send() gives its own haptic
                    Image(systemName: "arrow.up").font(.dl(.title3, .bold)).foregroundStyle(Color.dlNight)
                        .frame(width: DLSize.control, height: DLSize.control)
                        .background(Color.dlGo, in: RoundedRectangle.inner)
                }
                .buttonStyle(.dlPress)
                .disabled(bytes == 0 || bytes > limit)
                .opacity(bytes == 0 || bytes > limit ? 0.4 : 1)
                .accessibilityLabel("Send on Meshtastic")
                .accessibilityIdentifier("mesh-send")
            }
            .padding(4)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay(RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1))
        }
        .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.xs)
    }

    private func send() {
        if let why = onSend(text) {
            problem = why
            Haptics.error()
        } else {
            echo.sent(text)
            text = ""
            field += 1
            Haptics.tap()
        }
    }
}
