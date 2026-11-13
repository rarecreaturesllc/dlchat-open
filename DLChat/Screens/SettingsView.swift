import SwiftUI

/// Settings and safety in one screen. Safety (wipe, pressure mark, PIN, Face ID, duress PIN) comes first,
/// then your messages, connections, and help. Rarely used parts are folded so the screen stays short.
struct SettingsView: View {
    let lock: AppLock
    /// The compose model, which owns the pressure mark.
    var compose: ComposeModel?
    let groups: GroupModel
    let online: OnlineModel
    let mesh: MeshtasticModel
    let direct: DirectModel
    let wipe: () -> Bool
    let done: () -> Void
    @State private var notifyOn = Notifier.isOn()
    @State private var showingRadioSettings = false
    @State private var notifyDenied = false
    @State private var practicing = Launch().screen == .practice
    @State private var showingRules = Launch().screen == .radio || Launch().screen == .notice
    /// Turning the Meshtastic radio on for the first time: the radio rules must be accepted first.
    @State private var acceptingRadio = false
    @State private var document: SettingsText.Document?
    @State private var exported = ""
    @State private var experimenting = false
    @State private var newRelay = ""
    @State private var showingInternet = false
    @FocusState private var relayFocused: Bool
    /// Send Debug Logs: kept in memory only (no UserDefaults trace), like every other field here.
    @State private var problem = ""
    @State private var sendingLogs = false
    @State private var sendingAnonymously = false
    /// What happened to the last send; the explanation shows until there is one.
    @State private var logsStatus: String?
    @FocusState private var problemFocused: Bool

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text("Settings").font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }

                    heading("Safety")
                    SafetySection(lock: lock, compose: compose, wipe: wipe, close: done)

                    heading("Your messages")
                    messagesSection

                    heading("Connections")
                    internetSection
                    onlineSection
                    radioSection
                    notificationsSection

                    heading("Help")
                    helpSection

                    versionRow
                }
                .padding(DLSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("settings-scroll")
        }
        .preferredColorScheme(.dark)
        .tint(Color.dlGo)
        .task { groups.loadRetention(); refreshExport() }
        .sheet(isPresented: $practicing) { PracticeView { practicing = false } }
        .sheet(isPresented: $showingRules) { RadioNoticeView { showingRules = false } }
        .sheet(isPresented: $acceptingRadio) {
            RadioNoticeView(onContinue: { mesh.acceptLaw(); mesh.setOn(true); acceptingRadio = false },
                            continueTitle: RadioNotice.radioOnButton, extra: RadioNotice.radioOnAcceptance) { acceptingRadio = false }
        }
        .sheet(item: $document) { DocumentView(document: $0) { document = nil } }
        .sheet(isPresented: $experimenting) { ExperimentsView { experimenting = false } }
        .sheet(isPresented: $showingRadioSettings) {
            NavigationStack {
                MeshRadioSettingsView(mesh: mesh)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingRadioSettings = false } } }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingInternet) { InternetMessagingSettingsView(direct: direct) { showingInternet = false } }
    }

    // MARK: Your messages

    @ViewBuilder private var messagesSection: some View {
        subheading("Call sign")
        CallSignEditor(groups: groups)
        note("Up to 4 letters or numbers and a colour. Friends see it on your Chat messages so they know who wrote what. It's sealed inside each message, so relays and radios never see it. Anyone in a group can pick any call sign, so it isn't proof of who sent something. Wipe removes it.")

        ViewThatFits(in: .horizontal) {
            HStack { subheading("Keep messages for"); Spacer(); retentionPicker }
            VStack(alignment: .leading, spacing: DLSpace.xs) { subheading("Keep messages for"); retentionPicker }
        }
        note(groups.retention == .off
             ? "Nothing is kept, so a repeated message cannot be spotted."
             : "Older messages are erased from this phone automatically.")

        SettingsFold(title: "Export received messages", id: "settings-fold-export") {
            note(SettingsText.exportNote)
            if exported.isEmpty {
                Text("No received messages to export.").font(.dl(.body)).foregroundStyle(Color.dlText)
                    .accessibilityIdentifier("settings-export-empty")
            } else {
                ShareLink(item: exported) { Text("Export as text") }
                    .buttonStyle(.dlSecondary).accessibilityIdentifier("settings-export")
            }
        }
    }

    private var retentionPicker: some View {
        RetentionPicker(groups: groups, changed: refreshExport)
            .accessibilityIdentifier("settings-retention")
    }

    // MARK: Connections

    @ViewBuilder private var internetSection: some View {
        subheading("Internet Messaging")
        SettingsLink(title: "How messages reach you",
                     detail: direct.route == .privateRelays ? "Private relays" : direct.route == .publicRelays ? "Public relays" : "Private and public relays",
                     id: "settings-internet-messaging") { showingInternet = true }
        note("One-to-one chats with anyone who has DLChat, no phone number. Post-quantum end-to-end encryption, only over Tor. Add contacts under Chat.")
    }

    @ViewBuilder private var onlineSection: some View {
        subheading("Online group chat")
        Toggle("Send and receive online", isOn: Binding(get: { online.isOn }, set: { online.setEnabled($0) }))
            .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
            .accessibilityIdentifier("settings-online")
        note("Sealed with your phrase before they leave. Relays see that this phone posted, when, roughly how much, and your internet address unless Tor is on. Never the words, the group or the phrase. Relays may keep sealed copies for 14 days, and a wipe can't recall them.")
        if online.isOn {
            Toggle("Hide my internet address (Tor)", isOn: Binding(get: { online.torOn }, set: { online.setTor($0) }))
                .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
                .accessibilityIdentifier("settings-tor")
            note("Sends relay traffic through the Tor network, so relays see a Tor address instead of yours. Slower: connecting can take a minute, and each send a few seconds. Your internet provider can see that you use Tor, not what for.")
            if online.torOn, let status = TorStatus.text(online) {
                HStack {
                    Text(status).font(.dl(.footnote)).foregroundStyle(online.torFailed ? Color.dlWarn : Color.dlSoft)
                        .accessibilityIdentifier("settings-tor-status")
                    Spacer()
                    if online.torFailed {
                        Button("Try again") { Haptics.tap(); online.retryTor() }
                            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlGo).frame(minHeight: DLSize.control)
                    }
                }
            }
            SettingsFold(title: "Relays", summary: "\(online.relays.count)", id: "settings-fold-relays") {
                ForEach(online.relays, id: \.self) { relay in
                    HStack {
                        Text(relay).font(.dl(.body)).foregroundStyle(Color.dlText).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { Haptics.tap(); online.setRelays(online.relays.filter { $0 != relay }) }
                            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                            .frame(minHeight: DLSize.control)
                            .disabled(online.relays.count == 1)
                            .accessibilityLabel("Remove \(relay)")
                    }
                }
                TextField("wss://your.relay", text: $newRelay)
                    .focused($relayFocused).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                    .onSubmit(addRelay)
                    .dlField(focused: relayFocused) { relayFocused = true }
                    .accessibilityIdentifier("settings-relay-field")
                ButtonPair {
                    Button("Add relay", action: addRelay).buttonStyle(.dlSecondary)
                        .disabled(!newRelay.lowercased().hasPrefix("ws"))
                } second: {
                    Button("Use defaults") { online.setRelays(OnlineModel.defaultRelays) }
                        .buttonStyle(.dlSecondary)
                        .accessibilityLabel("Use the default relays")
                }
            }
            if CloudCarrier.isConfigured {
                Toggle("Notify me through iCloud", isOn: Binding(get: { online.cloudOn }, set: { on in Task { await online.setCloud(on) } }))
                    .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
                    .accessibilityIdentifier("settings-cloud")
                note("Also keeps a sealed copy in DLChat's iCloud mailbox so your phone can notify you even when DLChat is closed. The notification says only \"\(Notifier.text)\". Needs iCloud signed in. Apple sees which iCloud account posted and when, not what.")
            }
        }
    }

    @ViewBuilder private var radioSection: some View {
        subheading("Meshtastic radio")
        // Off until turned on here; the first time, the radio rules notice must be accepted.
        Toggle("Send and receive by radio", isOn: Binding(get: { mesh.isActive }, set: { on in
            if on && !mesh.lawAccepted { acceptingRadio = true } else { mesh.setOn(on) }
        }))
            .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
            .accessibilityIdentifier("settings-radio")
        note("Uses a Meshtastic LoRa radio over Bluetooth to reach other radios kilometres away, with no signal or internet. Messages are sealed before they reach the radio. Listeners can tell which radio sent something and when, never the words. Short messages only.")
        if mesh.isActive {
            Text(MeshStatus.text(mesh)).font(.dl(.footnote))
                .foregroundStyle(mesh.licensed ? Color.dlWarn : Color.dlSoft)
                .accessibilityIdentifier("settings-radio-status")
            if mesh.savedRadio == nil {
                note("DLChat connects to the nearest Meshtastic radio it finds, with nothing to tap.")
                // Radios passed over (forgotten, or a PIN not entered) can still be picked by hand.
                ForEach(mesh.radios) { radio in
                    Button("Connect to \(radio.name)") { mesh.choose(radio) }.buttonStyle(.dlSecondary)
                }
            } else {
                switch mesh.status {
                case .busy:
                    note("A radio talks to one app at a time. Close the Meshtastic app or disconnect the radio there, and DLChat connects on its own. Using it anyway shares it with that app, and each may miss some messages.")
                    Button("Use it anyway") { mesh.useHere(evenIfBusy: true) }.buttonStyle(.dlSecondary)
                        .accessibilityIdentifier("settings-radio-take")
                case .released where mesh.letGoByHand:
                    Button("Use radio here") { mesh.useHere() }.buttonStyle(.dlPrimary)
                        .accessibilityIdentifier("settings-radio-use")
                case .released:
                    EmptyView()
                default:
                    Button("Let go of radio") { mesh.letGo() }.buttonStyle(.dlSecondary)
                        .accessibilityIdentifier("settings-radio-letgo")
                }
                if mesh.autoPicked != nil || mesh.status == .connecting {
                    note("The first time, iOS may ask for the radio's Bluetooth PIN. It shows on the radio's screen, or is 123456 on radios with a fixed PIN. iOS requires this once per radio and DLChat cannot skip it. If no PIN is entered, DLChat moves on to the next radio it finds.")
                        .accessibilityIdentifier("settings-radio-pin")
                }
                let _ = mesh.mineVersion  // isMine lives in UserDefaults; this redraws when it changes
                if !mesh.isMine {
                    note("DLChat connected to the nearest radio on its own. Radios without a screen often use the same PIN, so it could be someone else's. Until you confirm it's yours, DLChat changes nothing on it: it does not turn off its location sharing or set its region.")
                    Button("This is my radio") { mesh.confirmMine() }
                        .buttonStyle(.dlPrimary).accessibilityIdentifier("settings-radio-mine")
                }
                let others = mesh.radios.filter { $0.id != mesh.savedRadio }
                ForEach(others) { radio in
                    Button("Use \(radio.name) instead") { mesh.choose(radio) }.buttonStyle(.dlSecondary)
                }
                if mesh.isMine, mesh.regionUnset, mesh.status == .ready, !mesh.applying {
                    if let region = mesh.suggestedRegion {
                        note("This radio has no region yet, so it cannot send. Set it to \(region.name), from your phone's country? Only pick a region where you are: radio frequencies are set by law.")
                        Button("Set region: \(region.name)") { mesh.setSuggestedRegion() }
                            .buttonStyle(.dlPrimary).accessibilityIdentifier("settings-radio-region")
                    } else {
                        note("This radio has no region yet, so it cannot send. DLChat does not know the right one for your country: set it once in the Meshtastic app.")
                    }
                }
                if let location = mesh.locationNote {
                    Text(location).font(.dl(.footnote))
                        .foregroundStyle(location.contains("could not") ? Color.dlWarn : Color.dlSoft)
                        .accessibilityIdentifier("settings-radio-location")
                }
                // Transmit power, hops, name and the rest: also reached from Chat > Manage Meshtastic.
                if mesh.isMine, mesh.status == .ready {
                    Button("Radio settings") { showingRadioSettings = true }.buttonStyle(.dlSecondary)
                        .accessibilityIdentifier("settings-radio-settings")
                }
                Button("Forget this radio") { mesh.forget() }.buttonStyle(.dlSecondary)
                    .accessibilityIdentifier("settings-radio-forget")
            }
        }
        if mesh.isActive {
            Toggle("Let go of the radio when I leave DLChat", isOn: Binding(get: { mesh.letsGoInBackground },
                                                                           set: { mesh.setLetsGoInBackground($0) }))
                .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
                .accessibilityIdentifier("settings-radio-background")
            note(mesh.letsGoInBackground
                 ? "A radio talks to one app at a time. DLChat lets go when you switch away, so the Meshtastic app can use it, and takes it back when you return. Radio messages cannot notify you while DLChat is closed."
                 : "DLChat stays connected while in the background, so radio messages can notify you while the phone is locked. Tap Let go of radio before using the Meshtastic app.")
            note("Once a radio is yours (chosen by hand, or confirmed), DLChat turns off its GPS and location sharing, and asks before setting a region. DLChat never sends through a radio in licensed mode, where encryption is not allowed.")
        }
    }

    @ViewBuilder private var notificationsSection: some View {
        subheading("Notifications")
        Toggle("Tell me when a message arrives", isOn: Binding(get: { notifyOn }, set: { on in
            Task { notifyOn = await Notifier.setOn(on); notifyDenied = on && !notifyOn }
        }))
            .font(.dl(.body)).foregroundStyle(Color.dlText).frame(minHeight: DLSize.control)
            .accessibilityIdentifier("settings-notify")
        note("The notification says only \"\(Notifier.text)\": no group, no sender, no words. Radio messages can notify you with no internet only while DLChat stays connected to your radio in the background (see Meshtastic radio above).")
        if notifyDenied {
            note("Notifications are off for DLChat in iOS. Allow them in iOS Settings > DLChat > Notifications.")
        }
    }

    // MARK: Help

    @ViewBuilder private var helpSection: some View {
        SettingsLink(title: "Practice drill", detail: "Try sending and receiving with a practice phrase", id: "practice-open") { practicing = true }
        SettingsLink(title: "Meshtastic radio rules", detail: "Read the radio rules notice again", id: "radio-rules-open") { showingRules = true }

        SettingsFold(title: "Send debug logs", id: "settings-fold-debug-logs") {
            note("To \(SupportMail.address)")
            TextField("What went wrong?", text: $problem, axis: .vertical)
                .lineLimit(3...8)
                .autocorrectionDisabled()
                .focused($problemFocused)
                .dlField(focused: problemFocused) { problemFocused = true }
                .accessibilityIdentifier("settings-debug-logs-field")
            Button(sendingAnonymously ? "Sending through Tor…" : "Send anonymously", action: sendAnonymously)
                .buttonStyle(.dlSecondary)
                .disabled(!online.canSendSupport || sendingAnonymously || sendingLogs || problemIsEmpty)
                .accessibilityIdentifier("settings-debug-logs-anonymous")
            Button(sendingLogs ? "Opening email…" : "Send by email") {
                Task {
                    sendingLogs = true
                    let opened = await SupportMail.send(problem: problem)
                    logsStatus = opened ? nil : SettingsText.debugLogsNoEmailApp
                    if opened { problem = "" }
                    sendingLogs = false
                }
            }
            .buttonStyle(.dlSecondary)
            .disabled(sendingLogs || sendingAnonymously || problemIsEmpty)
            .accessibilityIdentifier("settings-debug-logs-send")
            note(logsStatus ?? (online.canSendSupport ? SettingsText.debugLogsNote : SettingsText.debugLogsOfflineNote))
                .accessibilityIdentifier("settings-debug-logs-status")
        }

        // Controls come first; the explanation is one tap away rather than in front of them.
        SettingsFold(title: "What DLChat protects", id: "settings-protection") {
            note(SettingsText.deletionNote)
            Text("Protected").font(.dl(.headline)).foregroundStyle(Color.dlText).padding(.top, DLSpace.xs)
            bullets(SettingsText.protectedList)
            Text("Not protected").font(.dl(.headline)).foregroundStyle(Color.dlText).padding(.top, DLSpace.xs)
            bullets(SettingsText.notProtectedList)
        }

        SettingsFold(title: "Documents", id: "settings-fold-documents") {
            ForEach(SettingsText.documents) { doc in
                SettingsLink(title: doc.title, id: "settings-doc-\(doc.id)") { document = doc }
            }
        }
    }

    /// The version; on test builds a long press (or the VoiceOver action) opens Experiments.
    private var versionRow: some View {
        let info = Bundle.main.infoDictionary
        let version = "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return Text(version).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            .frame(maxWidth: .infinity, minHeight: DLSize.control, alignment: .leading)
            .contentShape(Rectangle())
            .onLongPressGesture { if Experiments.canOverride { experimenting = true } }
            .accessibilityIdentifier("settings-version")
            .modifier(ExperimentsAction(open: { experimenting = true }))
    }

    private var problemIsEmpty: Bool { problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Sealed to the developer and posted through Tor (OnlineModel.sendSupport); nothing identifies the sender.
    private func sendAnonymously() {
        Task {
            sendingAnonymously = true
            defer { sendingAnonymously = false }
            do {
                let relays = try await online.sendSupport(SupportMail.body(problem: problem))
                logsStatus = relays > 0 ? SettingsText.debugLogsSentAnonymously(relays) : SettingsText.debugLogsAnonymousFailed
                if relays > 0 { problem = "" }
            } catch {
                logsStatus = SettingsText.debugLogsTooLong
            }
        }
    }

    private func addRelay() {
        online.setRelays(online.relays + [newRelay])
        newRelay = ""
        relayFocused = false
    }

    private func refreshExport() {
        let names = Dictionary(uniqueKeysWithValues: groups.groups.map { ($0.id, $0.name) })
        exported = MessageExport.text(messages: groups.messages(), groupNames: names)
    }

    private func heading(_ text: String) -> some View {
        DLLegend(text)
    }

    private func subheading(_ text: String) -> some View {
        Text(text).font(.dl(.headline)).foregroundStyle(Color.dlText).padding(.top, DLSpace.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            ForEach(items, id: \.self) { item in
                Text("• " + item).font(.dl(.body)).foregroundStyle(Color.dlText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DocumentView: View {
    let document: SettingsText.Document
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.dlNight.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    HStack {
                        Text(document.title).font(.dl(.title2, .semibold)).foregroundStyle(Color.dlText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Done") { Haptics.tap(); done() }.font(.dl(.headline)).foregroundStyle(Color.dlText)
                            .frame(minWidth: DLSize.control, minHeight: DLSize.control)
                    }
                    ForEach(document.paragraphs, id: \.self) {
                        Text($0).font(.dl(.body)).foregroundStyle(Color.dlText).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DLSpace.md)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The gear button that opens `SettingsView`, which holds Safety too (wipe, PIN, Face ID).
struct SettingsButton: View {
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Image(systemName: "gearshape").font(.dl(.title3, .semibold)).foregroundStyle(Color.dlText)
                .frame(width: DLSize.control, height: DLSize.control)
                .background(Color.dlPanel, in: RoundedRectangle.key)
                .overlay { if contrast == .increased { RoundedRectangle.key.stroke(Color.dlSoft, lineWidth: 2) } }
        }
        .buttonStyle(.dlPress)
        .accessibilityLabel("Settings and safety")
        .accessibilityIdentifier("settings-button")
    }
}

/// Gives VoiceOver users the same way into Experiments, on test builds only.
private struct ExperimentsAction: ViewModifier {
    let open: () -> Void
    func body(content: Content) -> some View {
        if Experiments.canOverride {
            content.accessibilityAction(named: "Open experiments", open)
        } else {
            content
        }
    }
}
