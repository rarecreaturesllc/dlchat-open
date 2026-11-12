import DLCore
import SwiftUI
import UIKit

/// Adding an Internet Messages contact, as three plain steps: 1 share or open a one-time invite,
/// 2 wait for the other phone, 3 read the six safety words to each other.
struct AddContactView: View {
    let direct: DirectModel
    /// An invite link opened from outside (Camera, Messages): starts on "Use their invite" with it.
    var incoming: DirectInviteText?
    let openChat: (UUID) -> Void
    let done: () -> Void

    enum Mode: Hashable { case mine, theirs }
    @State private var mode: Mode = .mine
    @State private var name = ""
    @State private var pending: PendingInvite?
    /// The link to send: short once the sealed invite is on the relays, else the full one.
    @State private var shareURL: URL?
    @State private var finding = false
    @State private var working = false
    @State private var problem: String?
    @State private var pasted = ""
    @State private var scanning = false
    @State private var accepted: UUID?
    @State private var confirmingCancel = false
    @FocusState private var nameFocused: Bool
    @FocusState private var pasteFocused: Bool

    /// The contact made from our invite, once the other phone used it.
    private var joined: DirectContact? {
        guard let pending else { return nil }
        return direct.contacts.first { $0.inviteID == pending.id }
    }

    private var finished: DirectContact? {
        if let accepted { return direct.contact(accepted) }
        return joined
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    if let contact = finished {
                        connected(contact)
                    } else {
                        DLSegments(selection: $mode, options: [Mode.mine, .theirs]) { $0 == .mine ? "Show my invite" : "Use their invite" }
                        .accessibilityIdentifier("add-contact-mode")
                        nameField
                        if mode == .mine { mine } else { theirs }
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                            .accessibilityIdentifier("add-contact-problem")
                    }
                }
                .padding(DLSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dlNight)
            .navigationTitle("Add a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished == nil ? "Cancel" : "Close") {
                        Haptics.tap()
                        // An unused invite is withdrawn when this screen closes, so it cannot be used later.
                        // That also kills a link or code already sent, so ask first.
                        if pending != nil, joined == nil { confirmingCancel = true } else { done() }
                    }
                    .accessibilityIdentifier("add-contact-close")
                    .confirmationDialog("Cancel this invite?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                        Button("Cancel the invite", role: .destructive) {
                            if let pending, joined == nil { direct.cancelInvite(pending.id) }
                            done()
                        }
                        .accessibilityIdentifier("add-contact-cancel-invite")
                        Button("Keep waiting", role: .cancel) {}
                    } message: {
                        Text("The link and QR code you shared stop working. If they already opened it, they will not be connected.")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(pending != nil && joined == nil)
        .onAppear {
            name = direct.myName
            if let incoming { mode = .theirs; pasted = incoming.url.absoluteString }
        }
        .fullScreenCover(isPresented: $scanning) {
            QRScanView(title: "Scan their invite", rejected: "That is not a DLChat contact invite.", onFound: { code in
                guard let invite = DirectInviteText(text: code) else { return false }
                pasted = invite.url.absoluteString
                Task { await accept(invite) }
                return true
            }) { scanning = false }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DLSpace.xs) {
            Text("Your name for them").font(.dl(.headline)).foregroundStyle(Color.dlText)
            TextField("First name or nickname (optional)", text: $name)
                .focused($nameFocused).submitLabel(.done).autocorrectionDisabled()
                .onSubmit { direct.setMyName(name) }
                .dlField(focused: nameFocused) { nameFocused = true }
                .accessibilityIdentifier("add-contact-name")
            Text("Sealed inside the invite or first message, so only they see it.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    // MARK: My invite

    @ViewBuilder private var mine: some View {
        if let pending {
            step(1, "Let them scan this, or send the link")
            // The short link once a relay holds the sealed invite: a small code any camera reads off a screen.
            // Until then (and for a private-relays-only invite) the full invite, which is far denser.
            QRCodeBox(text: (shareURL ?? pending.invite.url).absoluteString, label: "QR code with your one-time contact invite")
                .accessibilityIdentifier("contact-invite-qr")
            if let shareURL {
                ShareLink(item: shareURL, subject: Text("DLChat invite"),
                          message: Text("Open this on your iPhone with DLChat installed. It works once.")) {
                    Label("Send the invite link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dlSecondary)
                .accessibilityIdentifier("contact-invite-share")
            } else {
                Button {} label: {
                    HStack { ProgressView(); Text("Preparing the link…") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.dlSecondary).disabled(true)
                .accessibilityIdentifier("contact-invite-share-preparing")
            }
            Text("Works once, for 24 hours. Anyone who opens it first becomes this contact, so send it only to them, ideally over a channel you trust.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
            step(2, "Waiting for their phone")
            HStack(spacing: DLSpace.sm) {
                ProgressView()
                Text(direct.problem ?? "Keep this screen open. It finishes when their first message arrives over Tor.")
                    .font(.dl(.footnote)).foregroundStyle(direct.problem == nil ? Color.dlSoft : Color.dlWarn)
            }
            .accessibilityIdentifier("contact-invite-waiting")
            step(3, "Then read the safety words to each other", dim: true)
        } else {
            step(1, "Make a one-time invite")
            Text(direct.privateUnavailable
                 ? "It carries your new keys and where to reach you. DLChat's private relays aren't set up yet, so messages to you come by public relays for now."
                 : "It carries your new keys and where to reach you, nothing else: no phone number, no account.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
            Button { Task { await makeInvite() } } label: {
                HStack { if working { ProgressView() }; Text(working ? "Connecting to Tor…" : "Make invite") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dlPrimary).disabled(working)
            .accessibilityIdentifier("contact-make-invite")
        }
    }

    private func makeInvite() async {
        direct.setMyName(name)
        working = true
        problem = nil
        defer { working = false }
        do {
            let made = try await direct.makeInvite()
            pending = made
            shareURL = nil
            working = false
            // The QR code shows at once; the short link follows once a relay holds the sealed invite.
            shareURL = await direct.publishLink(for: made) ? made.invite.link.url : made.invite.url
        } catch DirectError.needsNewerSystem {
            problem = "Internet Messages need iOS 26 or later on this iPhone."
        } catch {
            problem = "The invite could not be made. Try again."
        }
    }

    // MARK: Their invite

    @ViewBuilder private var theirs: some View {
        // Opened from their link: the invite is already here, so the one thing to do is connect. After a
        // failure the scan and paste choices come back.
        let fromLink = incoming != nil && pasted == incoming?.url.absoluteString && problem == nil
        if fromLink {
            step(1, "You opened their invite")
            Text("Tap Connect. It reaches them over Tor, which can take a minute the first time.")
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("contact-from-link")
        } else {
            step(1, "Scan or paste their invite")
            Button { scanning = true } label: {
                Label("Scan their QR code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.dlPrimary).disabled(working)
            .accessibilityIdentifier("contact-scan")
            TextField("Or paste the invite link", text: $pasted, axis: .vertical)
                .focused($pasteFocused).lineLimit(1...4).autocorrectionDisabled().textInputAutocapitalization(.never)
                .dlField(focused: pasteFocused) { pasteFocused = true }
                .accessibilityIdentifier("contact-paste")
        }
        let acceptButton = Button {
            guard let invite = DirectInviteText(text: pasted) else { problem = "That is not a DLChat contact invite."; return }
            Task { await accept(invite) }
        } label: {
            HStack { if working { ProgressView() }; Text(finding ? "Finding their invite…" : working ? "Connecting to Tor…" : fromLink ? "Connect" : "Add contact") }.frame(maxWidth: .infinity)
        }
        .disabled(working || pasted.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityIdentifier("contact-accept")
        if fromLink { acceptButton.buttonStyle(.dlPrimary) } else { acceptButton.buttonStyle(.dlSecondary) }
        step(2, "Then read the safety words to each other", dim: true)
    }

    private func accept(_ text: DirectInviteText) async {
        direct.setMyName(name)
        working = true
        problem = nil
        defer { working = false; finding = false }
        let invite: DirectInvite
        switch text {
        case .full(let full): invite = full
        case .short(let link):
            finding = true
            guard let fetched = await direct.fetchInvite(link) else {
                problem = "Couldn't find that invite online. It may have been used or expired, or the connection is down. Try again, or scan their QR code."
                return
            }
            invite = fetched
        }
        finding = false
        do {
            accepted = try await direct.accept(invite).id
            Haptics.success()
        } catch DirectError.needsNewerSystem {
            problem = "Internet Messages need iOS 26 or later on this iPhone."
        } catch {
            problem = "That invite could not be used. Ask them for a new one."
        }
    }

    // MARK: Done

    @ViewBuilder private func connected(_ contact: DirectContact) -> some View {
        Label("Connected with \(contact.name)", systemImage: "checkmark.seal.fill")
            .font(.dl(.title3, .bold)).foregroundStyle(Color.dlGo)
            .accessibilityIdentifier("contact-connected")
        step(accepted == nil ? 3 : 2, "Read the safety words to each other now")
        SafetyWordsPanel(words: contact.safetyWords)
        Text("Ask: \"Can you read me your six safety words?\" If theirs match yours, you're talking to each other and nobody in between.")
            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
        Button("Open chat") { openChat(contact.id) }
            .buttonStyle(.dlPrimary).accessibilityIdentifier("contact-open-chat")
    }

    private func step(_ number: Int, _ title: String, dim: Bool = false) -> some View {
        HStack(spacing: DLSpace.sm) {
            Text("\(number)").font(.dl(.headline)).foregroundStyle(Color.dlNight).frame(width: 28, height: 28)
                .background(dim ? Color.dlSoft : Color.dlGo, in: RoundedRectangle.inner).accessibilityHidden(true)
            Text(title).font(.dl(.headline)).foregroundStyle(dim ? Color.dlSoft : Color.dlText)
        }
        .padding(.top, DLSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)")
    }
}
