import DLCore
import SwiftUI

/// Which chat Send > Encrypt Words or Encrypt Sound posts into: a group, and one of its rooms.
struct ChatTarget: Equatable {
    var groupID: UUID
    var room: String
}

/// Pick a chat (only when there is more than one group or room) and post into it. The screen's other
/// buttons go in `before` and `after`, so they all sit together at the bottom of the same scroll.
/// `send` returns the problem to show, or nil once it is on its way.
struct PostToChatSection<Before: View, After: View>: View {
    let groups: [ChatGroup]
    @Binding var target: ChatTarget
    let what: String
    /// "Send" or "Share": the button reads "<verb> in <group name>".
    var verb = "Send"
    let send: () -> String?
    @ViewBuilder var before: () -> Before
    @ViewBuilder var after: () -> After
    @State private var problem: String?

    private var group: ChatGroup? { groups.first { $0.id == target.groupID } }

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            if groups.count > 1 {
                Picker("Chat", selection: Binding(get: { target.groupID }, set: { target = ChatTarget(groupID: $0, room: "") })) {
                    ForEach(groups) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu).frame(minHeight: DLSize.control, alignment: .leading)
                .accessibilityIdentifier("post-chat-group")
            }
            if let group, !group.rooms.isEmpty {
                Picker("Room", selection: $target.room) {
                    Text("Main").tag("")
                    ForEach(group.rooms, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).frame(minHeight: DLSize.control, alignment: .leading)
            }
            Text("\(verb) in \(group?.name ?? "Chat") posts \(what) in its chat. Everyone there can tap it to decrypt it in Receive.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.dl(.footnote)).foregroundStyle(Color.dlWarn)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("post-chat-problem")
            }
            before()
            Button("\(verb) in \(group?.name ?? "Chat")") { problem = send() }
                .buttonStyle(.dlPrimary).accessibilityIdentifier("post-chat-send")
            after()
        }
        .onChange(of: target) { problem = nil }
    }
}

/// Send > Encrypt Words: the sealed words, with Share in the chosen chat or Copy to clipboard (to send them any other way).
struct EncryptedWordsView: View {
    let groups: [ChatGroup]
    @State var target: ChatTarget
    /// Seals the message for a chat; nil when it could not (the Send screen says why).
    let seal: (ChatTarget) -> [String]?
    /// Posts the words in that chat; returns the problem to show, or nil once sent.
    let post: ([String], ChatTarget) -> String?
    let done: () -> Void
    @State private var words: [String] = []
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: DLSpace.md) {
                        HStack {
                            Text("Encrypted words").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                                .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                                .accessibilityIdentifier("encrypted-words-close")
                        }
                        Text("\(words.count) words").font(.dl(.headline)).foregroundStyle(Color.dlSoft)
                        Text(words.joined(separator: " ")).font(.dl(.title3, .semibold)).foregroundStyle(Color.dlText)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.dlPanel, in: RoundedRectangle.key)
                            .accessibilityIdentifier("encrypted-words")
                        Text("Only your group can decrypt them, in Receive.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: DLSpace.md)
                        PostToChatSection(groups: groups, target: $target, what: "these words", verb: "Share") {
                            post(words, target)
                        } before: {
                            EmptyView()
                        } after: {
                            Button(copied ? "Copied for 1 minute" : "Copy to clipboard") {
                                Hygiene.copyPlaintext(words.joined(separator: " "))
                                copied = true
                            }
                            .buttonStyle(.dlSecondary).disabled(words.isEmpty)
                            .accessibilityIdentifier("encrypted-words-copy")
                            .accessibilityHint("Then paste them into any app. The clipboard clears after 1 minute.")
                            .sensoryFeedback(.success, trigger: copied) { _, now in now }
                        }
                    }
                    .padding(DLSpace.md)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: target, initial: true) { _, chat in
            // Each chat has its own phrase, so the words are sealed again for the chat chosen. Nothing is
            // copied until Copy to clipboard is tapped.
            words = seal(chat) ?? []
            copied = false
        }
    }
}
