import DLCore
import SwiftUI
import UIKit

/// One Internet Messages conversation.
struct DirectChatView: View {
    let direct: DirectModel
    let contactID: UUID
    @State private var text = ""
    @State private var problem: String?
    @State private var details = false
    @FocusState private var focused: Bool
    /// A new box after each send, and the sent text kept out of it: voice typing writes it back.
    @State private var field = 0
    @State private var echo = SentEcho()

    var body: some View {
        VStack(spacing: 0) {
            if let contact = direct.contact(contactID) {
                header(contact)
                messages
                composer
            } else {
                Text("This contact was removed.").font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).padding()
                Spacer()
            }
        }
        .onAppear { direct.openContact = contactID }
        .onDisappear { if direct.openContact == contactID { direct.openContact = nil } }
        .sheet(isPresented: $details) {
            DirectContactDetails(direct: direct, contactID: contactID) { details = false }
        }
    }

    private func header(_ contact: DirectContact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { Haptics.tap(); details = true } label: {
                HStack(spacing: DLSpace.xs) {
                    Image(systemName: "lock.fill").foregroundStyle(Color.dlGo).accessibilityHidden(true)
                    Text(routeLine(contact)).font(.dl(.footnote)).foregroundStyle(Color.dlSoft).lineLimit(2)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(Color.dlSoft)
                }
                .frame(minHeight: DLSize.control).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Contact details and safety words")
            .accessibilityIdentifier("direct-details")
            if let note = direct.problem {
                Label(note, systemImage: "exclamationmark.triangle.fill").font(.dl(.footnote, .semibold))
                    .foregroundStyle(Color.dlWarn).accessibilityIdentifier("direct-problem")
            }
        }
        .padding(.horizontal, DLSpace.md)
    }

    private func routeLine(_ contact: DirectContact) -> String {
        let way: String
        switch contact.theirRoute {
        case .privateRelays: way = contact.theirQueue == nil ? "public relays" : "private relays"
        case .publicRelays: way = "public relays"
        case .both: way = contact.theirQueue == nil ? "public relays" : "private and public relays"
        }
        return "Post-quantum encrypted, over Tor, by \(way)"
    }

    private var messages: some View {
        let list = direct.messages(for: contactID)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if list.isEmpty {
                        Text("No messages yet. Before sharing anything private, check the safety words with them (tap the lock above).")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).frame(maxWidth: .infinity, alignment: .leading).padding(DLSpace.md)
                    }
                    ForEach(list) { m in bubble(m).id(m.id) }
                }
                .padding(.vertical, DLSpace.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("direct-scroll")
            .stayingAtNewest(proxy, conversation: contactID, newest: list.last?.id)
        }
    }

    /// One line of the log, as in the group chat.
    private func bubble(_ m: DirectChatMessage) -> some View {
        let time = m.sentAt.formatted(date: .omitted, time: .shortened)
        return LogRow(time: time, mine: m.outgoing) {
            Text(m.text).font(.dl(.body)).foregroundStyle(Color.dlText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let route = caption(m) { Text(route.uppercased()).dlCaps(.caption).foregroundStyle(Color.dlSoft) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((m.outgoing ? "You: " : "") + m.text + ". " + time + (caption(m).map { " · " + $0 } ?? ""))
        .accessibilityIdentifier(m.outgoing ? "direct-sent" : "direct-received")
    }

    /// What became of it; the time is in the log's gutter.
    private func caption(_ m: DirectChatMessage) -> String? {
        switch m.status {
        case .queued: return "waiting for Tor"
        case .sent: return "sent" + (m.via.map { " by \($0.replacingOccurrences(of: "+", with: " and "))" } ?? "")
        case .received: return nil
        }
    }

    /// The same box as group Chat: one line, grows to five as you type, then scrolls inside.
    private var composer: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.dl(.footnote)).foregroundStyle(Color.dlWarn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: DLSpace.xs) {
                TextField("Message", text: $text, axis: .vertical)
                    .focused($focused)
                    .chatKeyboard()
                    .chatBox()
                    .padding(.leading, 12)
                    .accessibilityIdentifier("direct-field")
                    // Focus moves to the new box once it is there, so the keyboard stays up for the next message.
                    .task(id: field) {
                        guard field > 0 else { return }
                        try? await Task.sleep(for: .milliseconds(100))
                        focused = true
                    }
                    .id(field)
                    .onChange(of: text) {
                        problem = nil
                        if echo.isEcho(text) { text = "" }
                    }
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.dl(.title3, .bold)).foregroundStyle(Color.dlNight)
                        .frame(width: DLSize.control, height: DLSize.control)
                        .background(Color.dlGo, in: RoundedRectangle.inner)
                }
                .buttonStyle(.dlPress)
                .disabled(isEmpty)
                .opacity(isEmpty ? 0.4 : 1)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("direct-send")
            }
            .padding(4)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay(RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1))
        }
        .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.xs)
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        do {
            try direct.send(text, to: contactID)
            echo.sent(text)
            text = ""
            problem = nil
            field += 1
            Haptics.tap()
        } catch DirectError.tooLarge {
            problem = "That message is too long. Split it in two."
            Haptics.warn()
        } catch {
            problem = "This message could not be encrypted."
            Haptics.warn()
        }
    }
}

/// A contact's safety words, name, how messages travel, and removal.
struct DirectContactDetails: View {
    let direct: DirectModel
    let contactID: UUID
    let done: () -> Void
    @State private var name = ""
    @State private var confirming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                if let contact = direct.contact(contactID) {
                    VStack(alignment: .leading, spacing: DLSpace.md) {
                        SafetyWordsPanel(words: contact.safetyWords)
                        Text("Name on this phone").font(.dl(.headline)).foregroundStyle(Color.dlText)
                        TextField("Name", text: $name)
                            .focused($nameFocused).submitLabel(.done).autocorrectionDisabled()
                            .onSubmit { direct.rename(contactID, to: name) }
                            .dlField(focused: nameFocused) { nameFocused = true }
                            .accessibilityIdentifier("direct-name")
                        Text("Only you see this name. They chose their own, and it is not checked.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                        Text("How it travels").font(.dl(.headline)).foregroundStyle(Color.dlText)
                        Text("Each message is sealed with a post-quantum Double Ratchet: new keys every turn, so old messages stay safe even if a phone is taken later. It leaves only through Tor. Messages to you come the way you picked in Settings > Internet Messaging; messages to them go the way they picked.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                        Button("Remove contact") { confirming = true }
                            .buttonStyle(.dlDanger).padding(.top, DLSpace.md).accessibilityIdentifier("direct-remove")
                    }
                    .padding(DLSpace.md)
                    .onAppear { name = contact.name }
                }
            }
            .background(Color.dlNight)
            .navigationTitle("Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); direct.rename(contactID, to: name); done() }
                }
            }
            .confirmationDialog("Remove this contact?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Remove and erase", role: .destructive) { direct.remove(contactID); done() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Erases this contact's keys and messages from this phone. To talk again you need a new invite.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The safety words (six for a contact), with what to do with them.
struct SafetyWordsPanel: View {
    let words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.sm) {
            Text("Safety words").font(.dl(.headline)).foregroundStyle(Color.dlText)
            Text(words.joined(separator: " · ")).font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                .accessibilityIdentifier("direct-safety-words")
            Text("Read these to each other on a call or in person. If they match, nobody else took your invite. They are not a password.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DLSpace.md).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dlPanel, in: RoundedRectangle.key)
        .overlay { RoundedRectangle.key.stroke(Color.dlGo.opacity(0.6), lineWidth: 1) }
    }
}
