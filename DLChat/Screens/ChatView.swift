import DLCore
import SwiftUI
import UIKit

/// The group's conversation: what was sent and received, by any way, oldest first, with a box to
/// send online. The first visit asks once whether to go online, and says what relays can see.
struct ChatView: View {
    let groups: GroupModel
    let compose: ComposeModel
    let online: OnlineModel
    let mesh: MeshtasticModel
    /// Encrypted words posted here: "Decrypt in Receive" pastes them there.
    var openWords: (([String]) -> Void)?
    /// An encrypted sound posted here, tapped: Receive plays it, then shows the message.
    var openSound: ((Data) -> Void)?
    /// Read receipts: called (after a short pause) while this chat is on screen and the app is open and unlocked.
    var markRead: ((ChatGroup) -> Void)?
    var canRead = false
    /// Read from the Vault only when something changed, never per redraw: each read decrypts the store.
    @State private var messages: [StoredMessage] = []
    /// Which ways the next messages go (the ^ menu). Everything available, until the person changes it.
    @State private var route = ChatRoute()
    @State private var choosingRoute = false
    /// The encrypted bubble whose Copy / Decrypt menu is open.
    @State private var menuFor: String?
    @State private var copiedWords = false
    @State private var copiedSound = false
    /// Swiped to reply: the next message answers this one, until sent or cancelled.
    @State private var replyingTo: StoredMessage?
    /// The original a tapped quote jumped to, lit briefly so the eye finds it.
    @State private var flashed: String?
    /// Long-pressed > Delete: asks once, then removes it from this phone only.
    @State private var deleting: StoredMessage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var group: ChatGroup? { groups.activeGroup }

    /// The group's own conversation is what is on screen (not a Meshtastic chat or the ask-once card).
    private var showsGroupChat: Bool { mesh.open == nil && online.enabled != nil }

    private struct ReloadKey: Equatable { let group: UUID?, version: Int, transient: Int, unkept: Int }

    private func reload() {
        guard let group else { messages = []; return }
        let stored = groups.chatMessages(groupID: group.id)
        let fresh = (stored + (online.transient + online.unkept).filter { $0.groupID == group.id }).sorted { $0.recordedAt < $1.recordedAt }
        // Only a message added to the same conversation animates in; switching groups swaps at once.
        let added = !messages.isEmpty && fresh.count > messages.count && fresh.first?.id == messages.first?.id
        if added && !reduceMotion { withAnimation(DLMotion.move) { messages = fresh } } else { messages = fresh }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let open = mesh.open {
                // A plain Meshtastic chat chosen in the Chat drawer; "Chats" above is the only way back. The group's own chat is untouched.
                MeshChatView(mesh: mesh, conversation: open).id(open)
            } else if group == nil {
                note("Create or join a group first, from the Chats list.")
                Spacer()
            } else if online.enabled == nil {
                // Scrolls, so at the largest text sizes the card can't outgrow the screen and push the bars out.
                ScrollView { askOnce.padding(.bottom, DLSpace.md) }
                    .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("chat-ask-scroll")
            } else {
                ChatStatusHeader(online: online, mesh: mesh).zIndex(1)  // its open lines lie over the messages
                conversation
                if copiedWords {
                    Label(copiedSound ? "Copied for 1 minute." : "Copied. Paste them in Receive, then tap Decrypt.", systemImage: "doc.on.doc")
                        .font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlGo)
                        .padding(.horizontal, DLSpace.md).accessibilityIdentifier("chat-copied-words")
                }
                ChatComposer(compose: compose, routeLabel: routeSummary,
                             replying: replyingTo.map { (title: $0.isOutgoing ? "Replying to your message" : "Replying to", text: quoteText($0)) },
                             onCancelReply: { replyingTo = nil },
                             onRoute: { choosingRoute = true }, onSend: send)
            }
        }
        .onChange(of: ReloadKey(group: group?.id, version: groups.chatVersion, transient: online.transient.count, unkept: online.unkept.count), initial: true) { reload() }
        .onChange(of: group?.id) { replyingTo = nil }
        // Waits a moment, so a burst of arrivals is one receipt and a glance past the tab is none.
        .task(id: [AnyHashable(groups.chatVersion), AnyHashable(group?.id), AnyHashable(canRead && showsGroupChat)]) {
            guard canRead, showsGroupChat, let group, let markRead else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { markRead(group) }
        }
        .sheet(isPresented: $choosingRoute) { routeSheet }
        .confirmationDialog("Delete this message?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { m in
            Button("Delete", role: .destructive) { delete(m) }.accessibilityIdentifier("chat-delete-confirm")
        } message: { m in
            Text("It's removed from this phone only. Friends keep their copy."
                 + (m.isOutgoing && m.via == "queued" ? " It hasn't gone out yet, so it won't be sent." : ""))
        }
    }

    // MARK: Ask once

    private var askOnce: some View {
        VStack(alignment: .leading, spacing: DLSpace.md) {
            Text("Chat online?").font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                .accessibilityAddTraits(.isHeader)
            Text("Send your group's messages over the internet through public relays, like a normal chat app. They're sealed with your phrase first, so relays see only that this phone posted, when, and roughly how much. Never the words, the group or the phrase.")
                .font(.dl(.body)).foregroundStyle(Color.dlText).fixedSize(horizontal: false, vertical: true)
            Text("Tor hides your internet address from relays. It's on by default and can take a minute to connect. Words, tones and QR still work with no internet.")
                .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
            Button("Turn on online chat") { online.setEnabled(true) }
                .buttonStyle(.dlPrimary).accessibilityIdentifier("online-on")
            Button("Not now") { online.setEnabled(false) }
                .buttonStyle(.dlSecondary).accessibilityIdentifier("online-not-now")
        }
        .padding(18).background(Color.dlPanel, in: RoundedRectangle.key)
        .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.sm)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        note("No messages yet. Say hello.")
                    }
                    ForEach(messages) { m in
                        bubble(m, proxy: proxy)
                            .modifier(SwipeToReply(enabled: canReply(m)) { reply(to: m) })
                            .id(m.id).transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Log rows run to the screen edge.
                .padding(.vertical, DLSpace.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat-scroll")
            .stayingAtNewest(proxy, conversation: group?.id, newest: messages.last?.id)
        }
    }

    /// One line of the log: time in the gutter, who in a tag, what was said, then how it travelled in caps.
    private func bubble(_ m: StoredMessage, proxy: ScrollViewProxy) -> some View {
        let mine = m.isOutgoing
        let carried = ChatCarry.parse(m.text)
        let row = LogRow(time: clock(m), day: day(m), mine: mine) {
            // A friend's call sign (Settings > Call sign), so you can tell who wrote what.
            if !mine, let sign = m.callSign { CallSignBadge(sign: sign).accessibilityIdentifier("chat-callsign") }
            if m.replyTo != nil { quote(of: m, proxy: proxy) }
            if let carried {
                carriedLabel(carried)
            // Words travel lowercase, so the note comes back (sent or received) as "decrypted".
            } else if m.text.caseInsensitiveCompare(DecodeModel.acknowledgedText) == .orderedSame {
                // Receive > Acknowledged: only this note, never the decrypted words.
                Label(DecodeModel.acknowledgedText, systemImage: "lock.open")
                    .font(.dl(.body, .semibold)).foregroundStyle(Color.dlText)
                    .accessibilityIdentifier("chat-decrypted")
            } else {
                // Copy lives in the long-press menu (with Reply and Delete), so no text selection here.
                Text(m.text).font(.dl(.body)).foregroundStyle(Color.dlText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Red only when it will not go out; waiting for a connection is normal, so it stays quiet.
            let stuck = m.via == "unsent" || (m.via == "queued" && !online.isOn)
            let route = detail(m)
            if !route.isEmpty {
                Label {
                    Text(route.uppercased()).dlCaps(.caption)
                } icon: {
                    if stuck { Image(systemName: "exclamationmark.triangle").font(.dl(.caption, .semibold)) }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(stuck ? Color.dlWarn : Color.dlSoft)
                .fixedSize(horizontal: false, vertical: true)
            }
            if m.duress {
                Label("Sent under pressure", systemImage: "exclamationmark.triangle")
                    .font(.dl(.caption, .semibold)).foregroundStyle(Color.dlWarn)
            }
        }
        return Group {
            if let carried {
                // A tap opens a small menu on the bubble (Copy, Decrypt), closed by a tap outside: nothing is
                // copied and Receive never opens from a stray touch. A touch that becomes a scroll opens nothing.
                // A popover, not a Menu: a Menu hides its label while open, so the bubble would vanish.
                Button { Haptics.tap(); menuFor = m.id } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens a menu to copy or decrypt it")
                    .accessibilityIdentifier(carried.kind == .words ? "chat-carried-words" : "chat-carried-sound")
                    .popover(isPresented: Binding(get: { menuFor == m.id }, set: { if !$0 { menuFor = nil } }),
                             attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        carriedMenu(carried).presentationCompactAdaptation(.popover)
                    }
            } else {
                row
            }
        }
        .overlay { Rectangle().stroke(Color.dlGo, lineWidth: DLStroke.strong).opacity(flashed == m.id ? 1 : 0).allowsHitTesting(false) }
        .animation(reduceMotion ? nil : DLMotion.exit, value: flashed == m.id)
        // Long press: Copy, Reply, Delete.
        .contentShape(.contextMenuPreview, Rectangle())
        .contextMenu { menu(for: m, carried: carried) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((mine ? "You: " : m.callSign.map { "From \($0.letters): " } ?? "Received: ") + spoken(m.text, carried: ChatCarry.parse(m.text)) + ". "
                            + (m.replyTo != nil ? "Reply to " + quoteSpoken(m) + ". " : "") + (day(m).map { $0 + ", " } ?? "") + clock(m) + (detail(m).isEmpty ? "" : " · " + detail(m)))
        .accessibilityAction(named: "Reply") { if canReply(m) { reply(to: m) } }
        .accessibilityAction(named: "Show original") { if let original = original(of: m) { jump(to: original, proxy: proxy) } }
        .accessibilityAction(named: "Delete") { deleting = m }
    }

    /// Our own: the moment we sent it. Received: the sender's time, which the format keeps coarse.
    private func when(_ m: StoredMessage) -> Date { m.isOutgoing ? m.recordedAt : m.sentAt }

    private func clock(_ m: StoredMessage) -> String { when(m).formatted(date: .omitted, time: .shortened) }

    /// Nil for today, else the short day ("Nov 10").
    private func day(_ m: StoredMessage) -> String? {
        Calendar.current.isDateInToday(when(m)) ? nil : when(m).formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Long press

    @ViewBuilder private func menu(for m: StoredMessage, carried: ChatCarry.Carried?) -> some View {
        if let carried {
            Button { Haptics.tap(); copy(carried) } label: { Label("Copy", systemImage: "doc.on.doc") }
                .accessibilityIdentifier("chat-carried-copy")
            Button { Haptics.tap(); decrypt(carried) } label: { Label("Decrypt", systemImage: "lock.open") }
                .accessibilityIdentifier("chat-carried-decrypt")
        } else if m.text.caseInsensitiveCompare(DecodeModel.acknowledgedText) != .orderedSame {
            Button { Haptics.tap(); Hygiene.copyPlaintext(m.text) } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if canReply(m) {
            Button { reply(to: m) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }
        Button(role: .destructive) { deleting = m } label: { Label("Delete", systemImage: "trash") }
            .accessibilityIdentifier("chat-delete")
    }

    /// From this phone only: a kept message is erased from the sealed store (and a relay's copy is not
    /// taken in again); one shown for this session only is dropped from memory. Nothing is sent to friends.
    private func delete(_ m: StoredMessage) {
        Haptics.tap()
        if replyingTo?.id == m.id { replyingTo = nil }
        if online.transient.contains(where: { $0.id == m.id }) || online.unkept.contains(where: { $0.id == m.id }) {
            online.dismiss(id: m.id)
        } else {
            groups.deleteMessage(m)
        }
    }

    // MARK: Replies

    /// A read-once message is gone once shown, so it cannot be answered by reference.
    private func canReply(_ m: StoredMessage) -> Bool { !online.transient.contains { $0.id == m.id } }

    private func reply(to m: StoredMessage) {
        Haptics.tap()
        replyingTo = m
    }

    /// The message a reply points at, from this phone's own chat. Nil when it is not here.
    private func original(of m: StoredMessage) -> StoredMessage? {
        guard let fingerprint = m.replyTo else { return nil }
        return messages.last { $0.id != m.id && $0.recordedAt <= m.recordedAt && $0.reference.fingerprint == fingerprint }
            ?? messages.last { $0.id != m.id && $0.reference.fingerprint == fingerprint }
    }

    /// What a quote shows of a message: its text, or only a label for encrypted words and sound.
    private func quoteText(_ m: StoredMessage) -> String {
        switch ChatCarry.parse(m.text)?.kind {
        case .words?: return "Encrypted words"
        case .sound?: return "Encrypted sound"
        case nil: return m.text
        }
    }

    private func quoteSpoken(_ m: StoredMessage) -> String {
        guard let original = original(of: m) else { return "a message not on this phone" }
        return (original.isOutgoing ? "you: " : "") + quoteText(original)
    }

    /// The small quote at the top of a reply. Tapping it scrolls to the original and lights it.
    @ViewBuilder private func quote(of m: StoredMessage, proxy: ScrollViewProxy) -> some View {
        let original = original(of: m)
        let ink = Color.dlText, soft = Color.dlSoft
        Button {
            guard let original else { return }
            Haptics.tap()
            jump(to: original, proxy: proxy)
        } label: {
            HStack(spacing: DLSpace.xs) {
                RoundedRectangle(cornerRadius: 2).fill(Color.dlGo).frame(width: 3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(original.map { $0.isOutgoing ? "Your message" : "Their message" } ?? "Reply")
                        .font(.dl(.caption, .semibold)).foregroundStyle(soft)
                    Text(original.map(quoteText) ?? "A message not on this phone")
                        .font(.dl(.footnote)).foregroundStyle(original == nil ? soft : ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, DLSpace.xs)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Color.dlText.opacity(0.08), in: RoundedRectangle.inner)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .disabled(original == nil)
        .accessibilityIdentifier("chat-reply-quote")
    }

    private func jump(to original: StoredMessage, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : DLMotion.move) { proxy.scrollTo(original.id, anchor: .center) }
        flashed = original.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flashed == original.id { flashed = nil }
        }
    }

    private func spoken(_ text: String, carried: ChatCarry.Carried?) -> String {
        switch carried?.kind {
        case .words?: return "Encrypted words, \(carried?.words.count ?? 0) words"
        case .sound?: return "Encrypted sound"
        case nil: return text.caseInsensitiveCompare(DecodeModel.acknowledgedText) == .orderedSame ? DecodeModel.acknowledgedText : text
        }
    }

    /// The menu a tap on an encrypted bubble opens: two keys, and a tap outside to go back.
    private func carriedMenu(_ carried: ChatCarry.Carried) -> some View {
        VStack(spacing: 0) {
            menuKey("Copy", "doc.on.doc", id: "chat-carried-copy") { copy(carried) }
            Rectangle().fill(Color.dlHairline).frame(height: DLStroke.hair)
            menuKey("Decrypt", "lock.open", id: "chat-carried-decrypt") { decrypt(carried) }
        }
        .frame(minWidth: 220)
        .presentationBackground(Color.dlPanel)
        .preferredColorScheme(.dark)
    }

    private func menuKey(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); menuFor = nil; action() } label: {
            Label(title, systemImage: icon).font(.dl(.headline)).foregroundStyle(Color.dlText)
                .frame(maxWidth: .infinity, minHeight: DLSize.primary, alignment: .leading)
                .padding(.horizontal, DLSpace.md).contentShape(Rectangle())
        }
        .buttonStyle(.dlPress)
        .accessibilityIdentifier(id)
    }

    /// Words are copied as the bare words Receive takes; a sound as its chat text, marker included.
    private func copy(_ carried: ChatCarry.Carried) {
        Hygiene.copyPlaintext(carried.kind == .words ? carried.words.joined(separator: " ") : carried.text)
        copiedSound = carried.kind == .sound
        copiedWords = true
        Task { try? await Task.sleep(for: .seconds(4)); copiedWords = false }
    }

    /// Opens it in Receive: words are pasted there, a sound is played there and then shown.
    private func decrypt(_ carried: ChatCarry.Carried) {
        switch carried.kind {
        case .words: openWords?(carried.words)
        case .sound: openSound?(carried.payload)
        }
    }

    /// Encrypted words show as the words; an encrypted sound as a wave with its length.
    @ViewBuilder private func carriedLabel(_ carried: ChatCarry.Carried) -> some View {
        let ink = Color.dlText, soft = Color.dlSoft
        switch carried.kind {
        case .words:
            Label("Encrypted words", systemImage: "lock").font(.dl(.caption, .semibold)).foregroundStyle(soft)
            Text(carried.words.joined(separator: " ")).font(.dl(.body)).foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap to copy or decrypt").font(.dl(.caption, .semibold)).foregroundStyle(Color.dlGo)
        case .sound:
            HStack(spacing: DLSpace.xs) {
                Image(systemName: "waveform").font(.dl(.title2, .semibold)).foregroundStyle(ink).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encrypted sound").font(.dl(.body, .semibold)).foregroundStyle(ink)
                    let seconds = Int(Modem.duration(bytes: carried.payload.count).rounded(.up))
                    Text("About \(seconds) seconds · tap to copy or decrypt").font(.dl(.caption, .semibold)).foregroundStyle(Color.dlGo)
                }
            }
        }
    }

    /// How it travelled and what became of it; the time is in the log's gutter.
    private func detail(_ m: StoredMessage) -> String {
        var parts: [String] = []
        if !m.room.isEmpty { parts.append("Room \(m.room)") }
        if m.isOutgoing {
            switch m.via {
            case "queued": parts.append(online.isOn ? "waiting for a connection" : "not sent: online chat is off")
            case "unsent": parts.append("not sent: nothing took it. Send it again.")
            case "nearby": parts.append("sent nearby")
            case let via?:
                // Name every route that took it: the radio, and relays with or without Tor.
                let routes = via.split(separator: "+").compactMap { route -> String? in
                    let relays = m.relays.map { $0 == 1 ? "1 relay" : "\($0) relays" }
                    switch route {
                    case "radio": return "by radio"
                    case "online-tor": return relays.map { "\($0) via Tor" } ?? "sending"
                    case "online-direct": return relays.map { "\($0), no Tor" } ?? "sending"
                    case "online": return relays.map { "on \($0)" } ?? "sending"
                    default: return nil
                    }
                }
                if !routes.isEmpty { parts.append("sent " + routes.joined(separator: " + ")) }
            case nil: break
            }
        }
        if let read = ReadReceipts.label(m, on: groups.receiptGroups.contains(m.groupID)) { parts.append(read) }
        if online.transient.contains(where: { $0.id == m.id }) { parts.append("not saved on either phone") }
        if online.unkept.contains(where: { $0.id == m.id }) { parts.append("not kept on this phone") }
        return parts.joined(separator: " · ")
    }

    /// Returns a problem to show under the field, or nil once the message is on its way. Publishing
    /// runs in the background so the next message can be typed at once.
    private func send() -> String? {
        guard let group else { return nil }
        compose.flush()
        let room = group.rooms.contains(compose.room) ? compose.room : ""
        if let problem = ChatSender.send(text: compose.text, flags: compose.flags, group: group, room: room, groups: groups,
                                         online: online, mesh: mesh, route: route, relaysAllSkipped: relaysAllSkipped,
                                         replyTo: replyingTo?.reference) {
            return problem
        }
        replyingTo = nil
        compose.sent()  // the hidden duress mark and read once apply to one message only
        Haptics.tap()
        return nil
    }

    /// Reads `online.connected` so the view redraws when a relay connects or drops.
    private var openRelays: [String] { _ = online.connected; return group.map { online.openRelays(for: $0.id) } ?? [] }
    private var relaysAllSkipped: Bool { !openRelays.isEmpty && openRelays.allSatisfy(route.skipped.contains) }

    /// What the next message uses, on the ^ button: "Radio + 3 relays", "Relays", "Radio only".
    private var routeSummary: String {
        let relayCount = online.isOn && route.relays && !relaysAllSkipped ? openRelays.filter { !route.skipped.contains($0) }.count : nil
        let radio = route.radio && mesh.isOn
        switch (radio, relayCount) {
        case (true, let n?): return n == 0 ? "Radio + relays when connected" : "Radio + \(n == 1 ? "1 relay" : "\(n) relays")"
        case (true, nil): return "Radio only"
        case (false, let n?): return n == 0 ? "Relays when connected" : (n == 1 ? "1 relay" : "\(n) relays")
        case (false, nil): return "Nothing chosen"
        }
    }

    private var routeSheet: some View {
        ChatRouteSheet(route: $route, relays: openRelays, onlineOn: online.isOn, tor: online.torOn,
                       radioOn: mesh.isOn, radioReady: mesh.isReady, radioName: mesh.radioName,
                       radiosHeard: mesh.nodes.count) { choosingRoute = false }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
            .frame(maxWidth: .infinity, alignment: .leading).padding(DLSpace.md)
    }
}

/// Seals text for one group's chat and sends it by every chosen way: Chat's own box, and Send >
/// Encrypt Words / Encrypt Sound posting into a chosen chat.
@MainActor
enum ChatSender {
    /// Nil once the message is on its way (publishing runs in the background), else the problem to show.
    static func send(text: String, flags: UInt8, group: ChatGroup, room: String, groups: GroupModel,
                     online: OnlineModel, mesh: MeshtasticModel, route: ChatRoute = ChatRoute(),
                     relaysAllSkipped: Bool = false, replyTo: ReplyTo? = nil) -> String? {
        guard let keySet = groups.keySets().first(where: { $0.groupID == group.id && $0.room == room })
        else { return "This group's key is missing. Join it again with its phrase." }
        // Two equal messages in one 5-minute slot differ only by a 6-bit random number. 1 time in 64 it comes
        // out the same, and the second would be taken for a repeat of the first: seal again until it is new here.
        var wire = Data()
        for _ in 0..<8 {
            guard let frame = try? Composer.composeNearby(text: text, keys: keySet.keys, flags: flags, replyTo: replyTo, callSign: groups.callSign)
            else { return "Type a message with letters or numbers first." }
            wire = NearbyWire.wire(frame: frame, ttl: NearbyWire.startTTL)
            guard let sealed = Receiver.readNearby(wire: wire, trying: [keySet.keys]), groups.holds(sealed, from: keySet) else { break }
        }
        // Every carrier drops a frame over this size, so say so before the field is cleared.
        guard wire.count <= NearbyWire.maxBytes else {
            return "Too long to send by chat. Shorten it by about \((wire.count - NearbyWire.maxBytes) * 100 / wire.count + 1)%."
        }
        let relays = online.isOn && route.relays && !relaysAllSkipped
        let radio = route.radio && mesh.isOn
        guard radio || relays else {
            return route == ChatRoute() ? "Chat has no way to send yet. Turn on online chat or the radio in Settings."
                                        : "Nothing is chosen to send it. Tap ^ and pick the radio or relays."
        }
        let byRadio = radio && mesh.send(wire)
        // Radio only and the radio could not take it: keep the text so nothing is lost.
        if !relays && !byRadio { return mesh.problem ?? "The radio is not connected. Tap ^ in Chat to send by relays instead." }
        let skipped = route.skipped
        Task { await online.send(wire: wire, keySet: keySet, sentBy: byRadio ? "radio" : nil, useRelays: relays, skipping: skipped) }
        return nil
    }
}

/// The message box. Its own view, so typing redraws only this, not the conversation above it.
private struct ChatComposer: View {
    let compose: ComposeModel
    let routeLabel: String
    /// Set while the next message is a reply: the heading, and what the quote shows of the original.
    var replying: (title: String, text: String)? = nil
    var onCancelReply: () -> Void = {}
    let onRoute: () -> Void
    let onSend: () -> String?
    @FocusState private var focused: Bool
    @State private var problem: String?
    /// A new box after each send: ends voice typing, which would otherwise write the sent text back.
    @State private var field = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            if let note = problem ?? compose.problem {
                Label(note, systemImage: "exclamationmark.triangle").font(.dl(.footnote)).foregroundStyle(Color.dlWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat-problem")
            }
            if let replying {
                HStack(spacing: DLSpace.xs) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.dlGo).frame(width: 3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(replying.title)
                            .font(.dl(.caption, .semibold)).foregroundStyle(Color.dlSoft)
                        Text(replying.text).font(.dl(.footnote)).foregroundStyle(Color.dlText).lineLimit(1)
                    }
                    Spacer(minLength: DLSpace.xs)
                    Button { Haptics.tap(); onCancelReply() } label: {
                        Image(systemName: "xmark").font(.dl(.footnote, .bold)).foregroundStyle(Color.dlSoft)
                            .frame(width: DLSize.control, height: DLSize.control)
                    }
                    .accessibilityLabel("Cancel reply")
                    .accessibilityIdentifier("chat-reply-cancel")
                }
                .padding(.leading, DLSpace.sm)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat-replying")
                .onAppear { focused = true }
            }
            // At accessibility text sizes the two options get their own row, so the message keeps the width.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: DLSpace.xs) { routeButton; readOnceButton }
                        HStack(alignment: .bottom, spacing: DLSpace.xs) { messageField; sendButton }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: DLSpace.xs) { routeButton; readOnceButton; messageField; sendButton }
                }
            }
            // One module holds the route, read-once, the field and Send; it grows taller for long text.
            .padding(4)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .overlay(RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: DLStroke.hair))
        }
        .padding(.horizontal, DLSpace.md).padding(.vertical, DLSpace.xs)
    }

    private var routeButton: some View {
        Button(action: { Haptics.tap(); onRoute() }) {
            Image(systemName: "chevron.up").font(.dl(.headline, .bold)).foregroundStyle(Color.dlSoft)
                .frame(width: DLSize.control, height: DLSize.control)
        }
        .accessibilityLabel("Send by")
        .accessibilityValue(routeLabel)
        .accessibilityIdentifier("chat-route")
    }

    private var readOnceButton: some View {
        Button { Haptics.tap(); compose.readOnce.toggle() } label: {
            Image(systemName: compose.readOnce ? "eye.slash.fill" : "eye")
                .font(.dl(.headline)).foregroundStyle(compose.readOnce ? Color.dlGo : Color.dlSoft)
                .contentTransition(.symbolEffect(.replace))  // the eye crossfades; iOS cuts it with Reduce Motion
                .frame(width: DLSize.control, height: DLSize.control)
        }
        .accessibilityLabel("Read once")
        .accessibilityValue(compose.readOnce ? "On" : "Off")
        .accessibilityIdentifier("chat-read-once")
    }

    private var messageField: some View {
        TextField("Message", text: Bindable(compose).text, axis: .vertical)
            .focused($focused)
            .chatKeyboard()
            .chatBox()
            .accessibilityIdentifier("chat-field")
            // Focus moves to the new box once it is there, so the keyboard stays up for the next message.
            // The old box drops focus as it goes (later, while Chat glides to the new message), so take it after that.
            .task(id: field) {
                guard field > 0 else { return }
                try? await Task.sleep(for: .milliseconds(100))
                focused = true
            }
            .id(field)
            .onChange(of: compose.text) { problem = nil }
    }

    private var sendButton: some View {
        Button {
            problem = onSend()
            if problem != nil { Haptics.warn() } else { field += 1 }
        } label: {
            Image(systemName: "arrow.up").font(.dl(.title3, .bold)).foregroundStyle(Color.dlNight)
                .frame(width: DLSize.control, height: DLSize.control)
                .background(Color.dlGo, in: RoundedRectangle.inner)
        }
        .buttonStyle(.dlPress)
        .disabled(compose.count == 0)
        .opacity(compose.count == 0 ? 0.4 : 1)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("chat-send")
    }
}

/// Swipe a bubble to the right to reply to it. The bubble follows the finger a little, a reply arrow
/// fades in behind it, and a tick is felt when letting go would reply. Vertical scrolling is untouched.
private struct SwipeToReply: ViewModifier {
    let enabled: Bool
    let onReply: () -> Void
    @State private var offset: CGFloat = 0
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let trigger: CGFloat = 56

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.dl(.headline)).foregroundStyle(armed ? Color.dlGo : Color.dlSoft)
                    .opacity(Double(min(offset / trigger, 1)))
                    .accessibilityHidden(true)
            }
            // The whole row takes the swipe, not only the bubble on its side of it.
            .contentShape(Rectangle())
            .simultaneousGesture(drag, including: enabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        // Global, so the start point can be compared with the page swipe's (see `PageSwipe.replyClaim`).
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                // Mostly sideways and to the right; anything else is a scroll.
                // The first points from the left edge belong to the swipe back to Chats.
                guard value.startLocation.x > EdgeSwipeBack<EmptyView, EmptyView>.edge, dx > 0, dx > abs(value.translation.height) * 1.5 else {
                    if offset != 0 { offset = 0; armed = false }
                    return
                }
                // This drag is a reply, so it must not also change tab.
                PageSwipe.replyClaim = value.startLocation
                offset = dx < trigger ? dx : trigger + (dx - trigger) * 0.2
                if (dx >= trigger) != armed {
                    armed = dx >= trigger
                    if armed { Haptics.select() }
                }
            }
            .onEnded { _ in
                if armed { onReply() }
                armed = false
                withAnimation(reduceMotion ? nil : DLMotion.exit) { offset = 0 }
            }
    }
}

/// Which ways Chat sends: the radio, and each connected relay. Receiving is not affected.
struct ChatRoute: Equatable {
    var radio = true
    var relays = true
    /// Relay addresses turned off one by one.
    var skipped: Set<String> = []
}

/// The ^ menu: what is connected, and which of it the next messages use.
private struct ChatRouteSheet: View {
    @Binding var route: ChatRoute
    let relays: [String]
    let onlineOn: Bool
    let tor: Bool
    let radioOn: Bool
    let radioReady: Bool
    let radioName: String?
    let radiosHeard: Int
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text("Send by").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    Text(summary).font(.dl(.headline)).foregroundStyle(Color.dlGo)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("route-summary")

                    // Shown off while the radio itself is off, so the switch never claims a route that cannot carry.
                    Toggle(isOn: Binding(get: { route.radio && radioOn }, set: { route.radio = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Radio").font(.dl(.body, .semibold)).foregroundStyle(Color.dlText)
                            Text(radioLine).font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Color.dlGo).frame(minHeight: DLSize.control).disabled(!radioOn)
                    .accessibilityIdentifier("route-radio")

                    Toggle(isOn: Binding(get: { route.relays && onlineOn }, set: { route.relays = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Relays (internet)").font(.dl(.body, .semibold)).foregroundStyle(Color.dlText)
                            Text(relayLine).font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Color.dlGo).frame(minHeight: DLSize.control).disabled(!onlineOn)
                    .accessibilityIdentifier("route-relays")

                    if onlineOn && route.relays && !relays.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(relays, id: \.self) { url in
                                Toggle(isOn: Binding(get: { !route.skipped.contains(url) },
                                                     set: { on in if on { route.skipped.remove(url) } else { route.skipped.insert(url) } })) {
                                    Text(url.replacingOccurrences(of: "wss://", with: "")).font(.dl(.subheadline)).foregroundStyle(Color.dlText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .tint(Color.dlGo).padding(.horizontal, DLSpace.md).frame(minHeight: 48)
                                if url != relays.last { Divider().overlay(Color.dlHairline) }
                            }
                        }
                        .background(Color.dlPanel, in: RoundedRectangle.key)
                        .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                    }
                    Text("Your choice applies to the messages you send until you change it. Messages still arrive by every way that is on.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(DLSpace.md)
            }
        }
        .preferredColorScheme(.dark)
    }

    /// "3 relays are connected and one radio"
    private var summary: String {
        let r = relays.count == 0 ? (onlineOn ? "No relays connected yet" : "Online chat is off")
                                  : "\(relays.count) \(relays.count == 1 ? "relay is" : "relays are") connected"
        let radio = radioReady ? "your radio is ready" : (radioOn ? "your radio is not connected" : "the radio is off")
        let heard = radioReady && radiosHeard > 0 ? ", hearing \(radiosHeard) other \(radiosHeard == 1 ? "radio" : "radios")" : ""
        return "\(r), and \(radio)\(heard)."
    }

    private var radioLine: String {
        if !radioOn { return "Off. Turn it on in Settings > Meshtastic radio." }
        let name = radioName ?? "Your radio"
        return radioReady ? "\(name), with no internet. Short messages only." : "\(name) is not connected; DLChat keeps trying."
    }

    private var relayLine: String {
        if !onlineOn { return "Off. Turn on online chat in Settings." }
        return (tor ? "Through Tor. " : "Without Tor. ") + (relays.isEmpty ? "Messages wait until a relay connects." : "Turn off any you don't want to use.")
    }
}
