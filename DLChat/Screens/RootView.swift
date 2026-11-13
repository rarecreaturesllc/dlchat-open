import DLCore
import SwiftUI
import UIKit

struct RootView: View {
    let start: Screen?
    @State private var groups: GroupModel
    @State private var compose: ComposeModel
    @State private var decode: DecodeModel
    @State private var lock: AppLock
    @State private var online: OnlineModel
@State private var mesh: MeshtasticModel
    @State private var direct: DirectModel
    /// Chat's open conversation; nil shows the drawer listing them all.
    @State private var chatSelection: ChatSelection?
    @State private var addingContact = false
    @State private var incomingContact: DirectInviteText?
    @State private var settings = false
    @State private var mode = 0
    @State private var banner = false
    @State private var bannerHide: Task<Void, Never>?
    @State private var reading = false
    @State private var showingQR = false
    @State private var playingTones = false
    @State private var encryptingWords = false
    @State private var creating = false
    /// First run, after the PIN: "Create a group for friends or family?" (see `FirstRunView`).
    @State private var welcoming = false
    @State private var invite: GroupInvite?
    @State private var inviteCheck: Result<PreparedGroup, JoinProblem>?
    @State private var picking = false
    @State private var managingContacts = false
    @State private var managingMesh = false
    @Environment(\.scenePhase) private var scenePhase
    /// DLChat went inactive only because the Face ID sheet came up (see the scene phase handler).
    @State private var faceIDSheetUp = false

    init(start: Screen?) {
        LaunchTiming.mark("root.init.begin")
        self.start = start
        // Nothing from Send or Receive survives a crash or kill: drafts live in memory only (GroupModel
        // also erases any an older build saved), and shared files left in the temporary folder go now.
        Hygiene.removeLeftoverFiles()
        let model = GroupModel.make()
        _groups = State(initialValue: model)
        let decodeModel = DecodeModel(groups: model)
        _decode = State(initialValue: decodeModel)
        let composeModel = ComposeModel(groups: model)
        _compose = State(initialValue: composeModel)
        // Nearby phones was removed: drop its old setting. Frames it held for passing on are no longer read
        // from the store, so they go the next time the store is saved.
        UserDefaults.standard.removeObject(forKey: "relayOn")
        let onlineModel = OnlineModel(groups: model)
        _online = State(initialValue: onlineModel)
        let directModel = DirectModel(online: onlineModel, vault: model.vault)
        _direct = State(initialValue: directModel)
        let meshModel = MeshtasticModel()
        meshModel.onWire = { onlineModel.storeFromRadio($0) }
        meshModel.useArchive(MeshArchiveFile(vault: model.vault))  // kept Meshtastic chats, only if the person chose to keep them
        _mesh = State(initialValue: meshModel)
        let appLock = AppLock(vault: model.vault) {
            Self.wipe(compose: composeModel, decode: decodeModel, online: onlineModel, mesh: meshModel, direct: directModel, groups: model)
        }
        #if DEBUG
        // The throwaway `-seed-demo` vault gets a known PIN (and starts unlocked), so UI tests and screenshots
        // skip the create-a-PIN screen. `-fresh-lock` leaves it out to test that screen.
        let arguments = LaunchSwitches.arguments
        if arguments.contains("-seed-demo"), !arguments.contains("-fresh-lock"), !appLock.hasPIN {
            _ = appLock.setPIN(Self.demoPIN)
        }
        // `-demo-faceid`: Face ID on for the demo PIN (simulator with Face ID enrolled), to measure unlocking.
        if arguments.contains("-seed-demo"), arguments.contains("-demo-faceid"), appLock.hasPIN, !appLock.biometricsOn {
            _ = appLock.turnOnBiometrics(pin: Self.demoPIN)
        }
        #endif
        _lock = State(initialValue: appLock)
        LaunchTiming.mark("root.init.end")
    }

    #if DEBUG
    static let demoPIN = "246810"
    #endif

    /// The one wipe sequence (duress PIN and panic wipe): screens holding plaintext are cleared first,
    /// then the Vault is erased. Returns false when the Vault could not be erased.
    private static func wipe(compose: ComposeModel, decode: DecodeModel,
                             online: OnlineModel, mesh: MeshtasticModel, direct: DirectModel, groups: GroupModel) -> Bool {
        compose.discard()
        decode.clear()
        direct.wipe()
        online.wipe()
        mesh.wipe()
        let wiped = groups.wipeEverything()
        Hygiene.clearAfterWipe()
        Notifier.wipe()
        return wiped
    }

    /// Panic wipe. The PIN is kept when the Vault could not be erased, so the lock still holds.
    private func wipeEverything() -> Bool {
        let wiped = Self.wipe(compose: compose, decode: decode, online: online, mesh: mesh, direct: direct, groups: groups)
        if wiped { lock.removePINs() }
        return wiped
    }

    private func showWords() {
        if compose.prepareWords() { reading = true }
    }

    private func showQR() {
        if compose.prepareQR() { showingQR = true }
    }

    private func showTones() {
        if compose.prepareTone() { playingTones = true }
    }

    /// Send > Encrypt Words: the words open on their own screen, already copied, with a way to post them in Chat.
    private func encryptWords() {
        if compose.prepareWords() { encryptingWords = true }
    }

    /// The chat Send posts into first: the active group and the room chosen on Send.
    private var startTarget: ChatTarget? {
        compose.group.map { ChatTarget(groupID: $0.id, room: $0.rooms.contains(compose.room) ? compose.room : "") }
    }

    private func group(_ target: ChatTarget) -> ChatGroup? { groups.groups.first { $0.id == target.groupID } }

    /// Posts carried words or sound in a chat, then shows that chat. Returns the problem to show, or nil once sent.
    private func post(_ text: String?, to target: ChatTarget, close: () -> Void) -> String? {
        guard let chat = group(target) else { return "That group is gone. Pick another chat." }
        guard let text else { return compose.problem ?? "This message could not be encrypted." }
        let room = chat.rooms.contains(target.room) ? target.room : ""
        if let problem = ChatSender.send(text: text, flags: compose.flags, group: chat, room: room,
                                         groups: groups, online: online, mesh: mesh) { return problem }
        compose.sent()
        close()
        if groups.activeGroup?.id != chat.id { groups.setActive(chat) }
        compose.syncGroup()
        mesh.openConversation(nil)
        chatSelection = .group(chat.id)
        mode = 2
        return nil
    }

    private var toneChat: ToneChat? {
        guard let start = startTarget else { return nil }
        return ToneChat(groups: groups.groups, start: start) { target in
            post(group(target).flatMap { compose.sealedSound(for: $0, room: target.room) }, to: target) { playingTones = false }
        }
    }

    /// Receive > Acknowledged: posts "Decrypted" (never the message) in the chat the message was sealed for,
    /// then shows that chat. Returns the problem to show, or nil once it is on its way.
    private func acknowledge(groupID: UUID, room: String) -> String? {
        guard let chat = groups.groups.first(where: { $0.id == groupID }) else { return "That group is gone." }
        let room = chat.rooms.contains(room) ? room : ""
        if let problem = ChatSender.send(text: DecodeModel.acknowledgedText, flags: 0, group: chat, room: room,
                                         groups: groups, online: online, mesh: mesh) { return problem }
        if groups.activeGroup?.id != chat.id { groups.setActive(chat) }
        compose.syncGroup()
        mesh.openConversation(nil)  // the group's own chat, not a plain Meshtastic one
        chatSelection = .group(chat.id)
        mode = 2
        return nil
    }

    /// Closes every screen and sheet at once, without animation (they may hold plaintext). Returns whether any was open.
    @discardableResult private func closeAll() -> Bool {
        let open = reading || showingQR || playingTones || encryptingWords || settings || picking || managingContacts || managingMesh || creating || welcoming || addingContact
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            reading = false; showingQR = false; playingTones = false; encryptingWords = false
            settings = false; picking = false; managingContacts = false; managingMesh = false; creating = false; welcoming = false; addingContact = false
        }
        return open
    }

    /// An invite link opens Join on the checked phrase and its safety words. Whatever was open closes first.
    private func open(_ found: GroupInvite) {
        let wasOpen = closeAll()
        Task {
            let started = ContinuousClock.now
            let checked = await groups.prepareJoin(found.phrase)
            // shortcut: fixed wait for the dismissal (and its onDismiss, which clears `invite`) to finish before
            // presenting; SwiftUI drops a sheet presented mid-dismiss. Upgrade if dismissals ever animate longer.
            if wasOpen { try? await Task.sleep(until: started + .milliseconds(600)) }
            invite = found
            inviteCheck = checked
            creating = true
        }
    }

    /// A contact invite link opens Add a contact on it. Whatever was open closes first, Add a contact and
    /// the first-run group question included: the link is what the person came for.
    private func open(_ contact: DirectInviteText) {
        let wasOpen = closeAll()
        // Set now, so first run (PIN, then the group question) sees it and does not cover this with the question.
        incomingContact = contact
        Task {
            // Same fixed wait as a group invite: SwiftUI drops a sheet presented mid-dismiss.
            if wasOpen { try? await Task.sleep(for: .milliseconds(600)) }
            addingContact = true
        }
    }

    /// Picking the Chat tab while a conversation is open there goes back to the drawer.
    private var tabSelection: Binding<Int> {
        Binding(get: { mode }, set: { new in
            if new == 2, mode == 2 { chatSelection = nil }
            mode = new
        })
    }

    /// A message arrived while another tab is showing.
    private func showBanner() {
        guard mode != 2, scenePhase == .active, !lock.coversApp else { return }
        banner = true
        UIAccessibility.post(notification: .announcement, argument: "New message")
        bannerHide?.cancel()
        bannerHide = Task { try? await Task.sleep(for: .seconds(6)); if !Task.isCancelled { banner = false } }
    }

    private func openChat(_ selection: ChatSelection) {
        switch selection {
        case .group(let id):
            if let group = groups.groups.first(where: { $0.id == id }), groups.activeGroup?.id != id { groups.setActive(group) }
            mesh.openConversation(nil)
            compose.syncGroup()
        case .mesh(let conversation):
            mesh.openConversation(conversation)
        case .direct:
            break
        }
        chatSelection = selection
    }

    private func title(of selection: ChatSelection) -> String {
        switch selection {
        case .group(let id): return groups.groups.first { $0.id == id }?.name ?? "Group"
        case .direct(let id): return direct.contact(id)?.name ?? "Contact"
        case .mesh(let conversation): return mesh.title(of: conversation)
        }
    }

    /// Chat: the drawer, or the chosen conversation under a "Chats" back bar.
    private var chatTab: some View {
        ZStack {
            // The drawer stays alive (untouchable, hidden from VoiceOver) under an open conversation, so
            // "Chats" goes back to it scrolled where it was left, not rebuilt at the top. The conversation
            // is opaque, so the drawer only shows while an edge swipe drags the conversation away.
            chatDrawer
                .allowsHitTesting(chatSelection == nil)
                .accessibilityHidden(chatSelection != nil)
            if let selection = chatSelection {
                // Swipe right from the left edge goes back to the list, like the "Chats" link.
                EdgeSwipeBack(back: { chatSelection = nil }) {
                    VStack(spacing: 0) {
                        ChatBackBar(title: title(of: selection), totalUnread: direct.totalUnread) { chatSelection = nil }
                        switch selection {
                        case .direct(let id):
                            DirectChatView(direct: direct, contactID: id).id(id)
                        case .group, .mesh:
                            ChatView(groups: groups, compose: compose, online: online, mesh: mesh, openWords: { words in
                                decode.clear(); decode.paste(words.joined(separator: " ")); mode = 1
                            }, openSound: { sound in
                                decode.clear(); decode.pendingSound = sound; mode = 1
                            }, markRead: { ReadReceipts.send(for: $0, groups: groups, online: online, mesh: mesh) },
                            canRead: scenePhase == .active && !lock.coversApp)
                        }
                    }
                } behind: {
                    EmptyView()
                }
            }
        }
    }

    private var chatDrawer: some View {
        ChatDrawerView(groups: groups, direct: direct, mesh: mesh, open: openChat,
                       newGroup: { creating = true }, addContact: { incomingContact = nil; addingContact = true },
                       manageGroups: { picking = true }, manageContacts: { managingContacts = true }, manageMesh: { managingMesh = true })
    }

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: 0) {
                // Groups and every other chat are reached from the Chat tab only; the bar holds Lock and Settings.
                HStack {
                    Spacer()
                    LockNowButton { lock.lock() }
                    SettingsButton { settings = true }
                }
                .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.xs)

                TabSlider(selection: tabSelection, labels: ["Send", "Receive", "Chat", "Map"])
                    .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.sm).padding(.bottom, DLSpace.xs)

                Group {
                    if mode == 3 { MeshMapView(mesh: mesh, online: online) } else if mode == 2 { chatTab } else if mode == 0 { SendView(compose: compose, show: showWords, encryptWords: encryptWords, showQR: showQR, showTones: showTones) } else { ReceiveView(decode: decode, groups: groups, acknowledge: acknowledge).id(groups.wipes) }
                }
                // Swiping the page left or right does what the tab slider does. An open conversation stays open.
                .pageSwipe($mode, count: 4, leadingEdge: mode == 2 && chatSelection != nil ? EdgeSwipeBack<EmptyView, EmptyView>.edge : 0)

            }
        }
        // A message arrived while another tab is showing: a small banner, no words, that opens Chat.
        .overlay(alignment: .top) { NewMessageBanner(visible: banner) { chatSelection = nil; mode = 2; banner = false } }
        .onChange(of: online.arrivals) { _, _ in showBanner() }
        .onChange(of: direct.arrivals) { _, _ in showBanner() }
        .onChange(of: online.torPort) { _, _ in direct.refresh() }
        .onChange(of: online.torOn) { _, _ in direct.refresh() }
        .onChange(of: mode) { _, m in if m == 2 { banner = false } }
        // Covers the main window's own content; the lock screen itself lives in `LockWindow`, above every sheet.
        .overlay { if lock.coversApp { Color.dlNight.ignoresSafeArea().accessibilityHidden(true) } }
        // Locked, or no PIN yet (first launch or an older install): either way nothing shows until a PIN is typed.
        .onChange(of: lock.coversApp, initial: true) { _, locked in
            LaunchTiming.mark(locked ? "lock.cover" : "unlocked")
            LockWindow.set(visible: locked, lock: lock, wipe: wipeEverything)
        }
        .tint(Color.dlGo)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $reading) {
            TeleprompterView(words: compose.words, lock: lock, wipe: wipeEverything) { reading = false; compose.duress = false }
        }
        .fullScreenCover(isPresented: $showingQR) {
            QRShowView(payload: compose.qr, lock: lock, wipe: wipeEverything) { showingQR = false; compose.duress = false }
        }
        .fullScreenCover(isPresented: $playingTones) {
            TonePlayView(samples: compose.tone, lock: lock, wipe: wipeEverything, chat: toneChat) { playingTones = false; compose.duress = false }
        }
        .sheet(isPresented: $encryptingWords) {
            if let start = startTarget {
                EncryptedWordsView(groups: groups.groups, target: start,
                                   seal: { target in group(target).flatMap { compose.sealedWords(for: $0, room: target.room) } },
                                   post: { words, target in post(ChatCarry.text(words: words), to: target) { encryptingWords = false } },
                                   done: { encryptingWords = false })
            }
        }
        .sheet(isPresented: $settings) { SettingsView(lock: lock, compose: compose, groups: groups, online: online, mesh: mesh, direct: direct, wipe: wipeEverything) { settings = false } }
        // No onDismiss clearing `incomingContact`: a link arriving while this is open closes and reopens it,
        // and that dismissal would wipe the new link. Its own buttons and opening from the drawer clear it.
        .sheet(isPresented: $addingContact) {
            AddContactView(direct: direct, incoming: incomingContact, openChat: { id in
                addingContact = false
                incomingContact = nil
                chatSelection = .direct(id)
                mode = 2
            }) { addingContact = false; incomingContact = nil }
        }
        .sheet(isPresented: $picking) {
            GroupListView(groups: groups, mesh: mesh) { picking = false }
        }
        .sheet(isPresented: $managingContacts) {
            InternetManageView(direct: direct, openChat: { id in
                managingContacts = false
                chatSelection = .direct(id)
                mode = 2
            }) { managingContacts = false }
        }
        .sheet(isPresented: $managingMesh) { MeshManageView(mesh: mesh) { managingMesh = false } }
        .sheet(isPresented: $welcoming) { FirstRunView(model: groups) { welcoming = false } }
        .sheet(isPresented: $creating, onDismiss: { invite = nil; inviteCheck = nil }) {
            GroupSetupView(model: groups, invite: invite, checked: inviteCheck) { creating = false }.id(invite)
        }
        .onOpenURL { url in
            if let found = GroupInvite(url: url) { open(found) }
            else if let contact = DirectInviteText(text: url.absoluteString) { open(contact) }
        }
        .onAppear {
            ScreenShield.protectAppWindows()
            if Hygiene.screenIsCaptured { PrivacyCoverWindow.set(visible: true) }
        }
        // Screenshots and recordings of the app come out blank; re-checked whenever iOS may have re-attached a window.
        .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in
            ScreenShield.protectAppWindows()
        }
        // Covered when not active, and while the screen is recorded or mirrored so no message is captured.
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            PrivacyCoverWindow.set(visible: scenePhase != .active || Hygiene.screenIsCaptured)
        }
        .onChange(of: scenePhase) { _, phase in
            LaunchTiming.mark("scene.\(phase)")
            // Locked with Face ID on: ask before anything else here, so the sheet is not kept waiting.
            if phase == .active, !LockView.holdsBiometrics { lock.askForBiometricsIfDue() }
            if phase == .active { ScreenShield.protectAppWindows() }
            PrivacyCoverWindow.set(visible: phase != .active || Hygiene.screenIsCaptured)
            // The Face ID sheet makes DLChat inactive while it is up. That is not leaving the app, so relays,
            // Internet Messages and the radio are not stopped and restarted around it (which made unlocking slow).
            // Going to the background while the sheet is up still runs everything below.
            if phase == .inactive, lock.biometricPromptOpen { faceIDSheetUp = true; return }
            if phase == .active, faceIDSheetUp { faceIDSheetUp = false; return }
            faceIDSheetUp = false
            if phase != .active { compose.flush() } else { groups.purgeExpired(); direct.purgeExpired(); Notifier.clear() }
            online.setActive(phase == .active)
            direct.setActive(phase == .active)
            if phase == .background { lock.lock() }
            // Not on .inactive (Control Center, a call banner): only when DLChat really leaves or returns.
            if phase == .background { mesh.setForeground(false); mesh.saveNow() } else if phase == .active { mesh.setForeground(true); mesh.purgeExpired() }
        }
        .onChange(of: groups.groups) { _, _ in compose.syncGroup(); decode.refreshKeys(); online.refresh() }
        // The radio is off until turned on in Settings; once on, it starts when there is a group to carry.
        .onChange(of: groups.groups.isEmpty, initial: true) { _, empty in if !empty { mesh.startIfWanted() } }
        .onChange(of: groups.activeGroup?.id) { _, _ in compose.syncGroup() }
        // A wipe from the lock screen must not leave open screens behind it. No animation: they may hold plaintext.
        .onChange(of: groups.wipes) { _, _ in closeAll(); incomingContact = nil }
        // After a wipe the next open asks for a new PIN (see AppLock.lock()); once it is made, setup carries on
        // with the group question, as on first run. The first-run case is already open from `.task` below.
        .onChange(of: lock.mustCreatePIN) { was, now in
            guard was, !now, !welcoming, invite == nil, incomingContact == nil, !addingContact, Onboarding.shouldAsk(hasGroups: !groups.groups.isEmpty) else { return }
            welcoming = true
        }
        .task {
            LaunchTiming.mark("root.task.begin")
            defer { LaunchTiming.mark("root.task.end") }
            #if DEBUG
            // The drawer's folded sections are remembered between launches; a reset starts with them all open.
            if LaunchSwitches.arguments.contains("-reset-demo") { RadioNotice.reset(); Onboarding.reset(); online.wipe(); mesh.wipe(); UserDefaults.standard.removeObject(forKey: "drawer.collapsed") }
            // UI tests point online chat at a local address so they never post to real relays.
            if let relay = UserDefaults.standard.string(forKey: "online-relays") { online.setRelays([relay]) }
            // ...and can keep Tor off, so they never reach the Tor network either.
            if LaunchSwitches.arguments.contains("-no-tor") { online.setTor(false) }
            // `-store-shots`: Chat opens on the conversation, past the ask-once card.
            if LaunchSwitches.arguments.contains("-store-shots") { online.setEnabled(true) }
            // Internet Messages against a local relay (relay/README.md), without Tor.
            if let relay = UserDefaults.standard.string(forKey: "direct-relay") {
                direct.allowWithoutTor = true
                direct.setPrivateRelays([relay])
            }
            await groups.seedDemoIfNeeded()
            groups.seedHistoryIfAsked()
            #endif
            compose.syncGroup()
            decode.refreshKeys()
            groups.purgeExpired()
            direct.purgeExpired()
            online.setActive(scenePhase == .active)
            direct.setActive(scenePhase == .active)
            switch start {
            case .decode: mode = 1
            case .readout: showWords()
            case .qr: showQR()
            case .scan, .listen: mode = 1
            case .tones: showTones()
            case .create: creating = true
            case .groups: picking = true
            case .practice, .radio, .notice, .settings, .safety: settings = true
            case .meshmap: mode = 3
            case .chat:
                if let group = groups.activeGroup { chatSelection = .group(group.id) }
                mode = 2
            // First run (or no group and the question never answered): the PIN screen first, then "Create a
            // group for friends or family?", unless an invite link is already opening Join or Add a contact. Asked once: after
            // Skip, later launches open on the app with no group.
            default: if Onboarding.shouldAsk(hasGroups: !groups.groups.isEmpty) && invite == nil && incomingContact == nil { welcoming = true }
            }
        }
    }
}

private struct SendView: View {
    let compose: ComposeModel
    let show: () -> Void
    let encryptWords: () -> Void
    let showQR: () -> Void
    let showTones: () -> Void
    @FocusState private var focused: Bool

    private func toggleDuress() {
        compose.duress.toggle()
        Haptics.tap()
    }

    var body: some View {
        // Scrolls only when the content does not fit (large text), so the top bar stays on screen. One copy of
        // `content`: ViewThatFits built two message fields on one focus flag, so focus could land on the hidden one.
        GeometryReader { geo in
            ScrollView { content.frame(minHeight: geo.size.height, alignment: .top) }
                .scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
        }
    }

    private var off: Bool { compose.count == 0 || compose.group == nil }

    /// Message on top, the control deck straight under it.
    private var content: some View {
        VStack(spacing: DLSpace.md) {
            TextField("Type your message", text: Bindable(compose).text, axis: .vertical)
                .accessibilityIdentifier("compose-field")
                .focused($focused).submitLabel(.done)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                // A compact box of four lines; longer text scrolls inside, so the deck below never moves while typing.
                // (A box that grows, `.lineLimit(3...6)`, fails the system accessibility audit on this screen.)
                .lineLimit(4, reservesSpace: true)
                .dlField(focused: focused) { focused = true }
                // The keyboard's return key closes the keyboard; a message has no line breaks to keep.
                .onChange(of: compose.text) { _, text in
                    guard text.contains(where: \.isNewline) else { return }
                    compose.text = text.filter { !$0.isNewline }
                    focused = false
                }
            if let group = compose.group, !group.rooms.isEmpty {
                Picker("Room", selection: Bindable(compose).room) {
                    Text("Main").tag("")
                    ForEach(group.rooms, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).frame(minHeight: DLSize.control, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let note = compose.problem ?? (compose.group == nil ? "Create or join a group first, in Chat." : nil) {
                Text(note).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).frame(maxWidth: .infinity, alignment: .leading)
            }
            // The readout: how many words the read-out will be, and which group (and room) it is sealed for.
            Readout(value: String(format: "%02d", compose.count), legend: "words to say",
                    detail: compose.group.map { "to \($0.name)" + (compose.room.isEmpty ? "" : " · \(compose.room)") })
                .accessibilityElement(children: .combine)
                // Hidden option: no mark on screen, only a haptic. VoiceOver gets an action instead of the long press.
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0) { toggleDuress() }
                .accessibilityAction(named: compose.duress ? "Remove pressure mark" : "Mark as sent under pressure") { toggleDuress() }
            // Three keys for the other carriers, then the one green bar in reach of a thumb.
            KeyRow {
                // Copies the sealed words and offers to post them in a chat; the other person pastes them in Receive > Decrypt.
                Button { focused = false; encryptWords() } label: { KeyLabel(title: "Encrypt words", icon: "lock.doc") }
                    .accessibilityIdentifier("copy-words")
                Button { focused = false; showTones() } label: { KeyLabel(title: "Encrypt sound", icon: "waveform") }
                    .accessibilityIdentifier("play-tones")
                Button { focused = false; showQR() } label: { KeyLabel(title: "Show QR code", icon: "qrcode") }
                    .accessibilityIdentifier("show-qr")
            }
            .buttonStyle(DLKeyStyle()).disabled(off)
            Button("Show the words") { focused = false; show() }
                .buttonStyle(.dlPrimary).disabled(off)
        }
        .padding(.horizontal, DLSpace.md).padding(.top, DLSpace.xs).padding(.bottom, DLSpace.xs)
        .contentShape(Rectangle()).onTapGesture { focused = false }
    }
}

private struct TeleprompterView: View {
    let words: [String]
    let lock: AppLock
    let wipe: () -> Bool
    let done: () -> Void
    @State private var step = 0
    @State private var safety = false
    @ScaledMetric(relativeTo: .largeTitle) private var wordSize = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Words empty out during a wipe while this screen is still closing.
        let groups = words.isEmpty ? [[]] : words.chunked(3)
        let i = min(step, groups.count - 1)
        ZStack {
            Color.dlNight.ignoresSafeArea()
            VStack(spacing: DLSpace.lg) {
                let bar = SegmentMeter(step: i + 1, total: groups.count)
                let controls = Group {
                    Text("\(i + 1)/\(groups.count)").font(.dlMono(.headline)).foregroundStyle(Color.dlSoft)
                    SafetyButton { safety = true }
                    Button("Close") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                        .lineLimit(1).fixedSize().frame(minHeight: DLSize.control)
                }
                // At accessibility sizes the controls fill the row, so the bar gets its own.
                if typeSize.isAccessibilitySize {
                    VStack(spacing: DLSpace.sm) { HStack { controls }.frame(maxWidth: .infinity, alignment: .trailing); bar }
                } else {
                    HStack { bar; controls }
                }
                Spacer(minLength: 0)
                VStack(spacing: DLSpace.lg) {
                    ForEach(Array(groups[i].enumerated()), id: \.offset) { _, w in
                        Text(w).font(.custom("Manrope", fixedSize: wordSize).weight(.bold))
                            .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(Color.dlText)
                    }
                }
                .id(i)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(groups[i].joined(separator: " "))
                .accessibilityIdentifier("readout-words")
                Spacer(minLength: 0)
                HStack(spacing: DLSpace.sm) {
                    Button("Back") { withAnimation(DLMotion.move) { step = max(0, i - 1) } }
                        .buttonStyle(.dlSecondary).frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 140).disabled(i == 0)
                    Button(i == groups.count - 1 ? "Say \"over\"" : "Next") {
                        if i == groups.count - 1 { done() } else { withAnimation(DLMotion.move) { step = i + 1 } }
                    }
                    .buttonStyle(.dlPrimary)
                }
            }
            .padding(DLSpace.md)
        }
        .sheet(isPresented: $safety) { SafetyView(lock: lock, wipe: { let ok = wipe(); if ok { done() }; return ok }) { safety = false } }
        .onAppear { step = Launch().screen == .readout ? 2 : 0 }
    }
}

/// The in-app "New message" banner: no group, sender or words, just a way into Chat.
private struct NewMessageBanner: View {
    let visible: Bool
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if visible {
                Button(action: { Haptics.tap(); open() }) {
                    HStack(spacing: DLSpace.sm) {
                        Circle().fill(Color.dlGo).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text("New message").font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlText)
                        Text("Open Chat").font(.dl(.subheadline)).foregroundStyle(Color.dlGo)
                    }
                    .padding(.horizontal, DLSpace.md).frame(minHeight: DLSize.control)
                    .background(Color.dlPanel, in: RoundedRectangle.key)
                    .overlay { RoundedRectangle.key.stroke(Color.dlHairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .padding(.top, DLSpace.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("new-message-banner")
            }
        }
        .animation(reduceMotion ? nil : DLMotion.move, value: visible)
    }
}
