import DLCore
import SwiftUI

/// Settings > Internet Messaging: how messages reach this phone (private relays, public relays, both),
/// the private relay list, and how long messages are kept.
struct InternetMessagingSettingsView: View {
    let direct: DirectModel
    let done: () -> Void
    @State private var newRelay = ""
    @FocusState private var relayFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    DLLegend("How messages reach you")
                    choice(.privateRelays, title: "Private relays", badge: "Strongest",
                           text: "DLChat's own servers, reachable only as Tor onion services. They never see your internet address, delete each message once it's delivered, and can't link the two ends of a chat. If they're down, messages wait.")
                    choice(.publicRelays, title: "Public relays", badge: "Default",
                           text: "No DLChat servers involved. Uses community Nostr relays, the same ones group chats use. Run by strangers: they may keep sealed messages for weeks, can see when your mailbox gets posts, and may drop some.")
                    choice(.both, title: "Both", badge: nil,
                           text: "Most reliable. Messages come by both routes and the second copy is dropped. The public relays then see your timing too.")
                    if direct.privateUnavailable {
                        Label("DLChat's private relays aren't set up yet, so messages to you come by public relays until they are.",
                              systemImage: "info.circle")
                            .font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlWarn)
                            .accessibilityIdentifier("im-private-unavailable")
                    }
                    Text("This applies to new contacts. Messages to others always go the way they picked. Everything is end-to-end encrypted with post-quantum keys and sent only over Tor whichever you pick.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)

                    DLLegend("Private relays")
                    if direct.privateRelays.isEmpty {
                        Text("None yet.").font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                    }
                    ForEach(direct.privateRelays, id: \.self) { relay in
                        HStack {
                            Text(relay).font(.dl(.body)).foregroundStyle(Color.dlText).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { Haptics.tap(); direct.setPrivateRelays(direct.privateRelays.filter { $0 != relay }) }
                                .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn).frame(minHeight: DLSize.control)
                                .accessibilityLabel("Remove \(relay)")
                        }
                    }
                    TextField("http://….onion", text: $newRelay)
                        .focused($relayFocused).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                        .onSubmit(addRelay)
                        .dlField(focused: relayFocused) { relayFocused = true }
                        .accessibilityIdentifier("im-relay-field")
                    Button("Add relay", action: addRelay).buttonStyle(.dlSecondary)
                        .disabled(!DirectModel.isAllowedPrivateRelay(newRelay.trimmingCharacters(in: .whitespaces)))
                    Text("Anyone can run one (relay/README.md in DLChat's source). A relay only ever holds sealed messages.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)

                    DLLegend("Disappearing messages")
                    DLSegments(selection: Binding(get: { direct.keep }, set: { direct.setKeep($0) }),
                               options: [Retention.day, .week, .month, .forever]) { $0.title }
                    .accessibilityIdentifier("im-keep")
                    Text("Internet Messages on this phone are erased after this long. 7 days unless you change it. Wipe erases them at once.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)

                    DLLegend("Notifications")
                    Text("DLChat doesn't use Apple's push service, so Apple never learns when you get a message. New messages arrive while DLChat is open.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(DLSpace.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dlNight)
            .navigationTitle("Internet Messaging")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Haptics.tap(); done() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func addRelay() {
        direct.setPrivateRelays(direct.privateRelays + [newRelay])
        newRelay = ""
        relayFocused = false
    }

    private func choice(_ route: DirectRoute, title: String, badge: String?, text: String) -> some View {
        let selected = direct.route == route
        return Button { Haptics.tap(); direct.setRoute(route) } label: {
            HStack(alignment: .top, spacing: DLSpace.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.dl(.title3)).foregroundStyle(selected ? Color.dlGo : Color.dlSoft).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
                        if let badge {
                            Text(badge).font(.dl(.caption, .bold)).foregroundStyle(Color.dlNight)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.dlGo, in: RoundedRectangle.tag)
                        }
                    }
                    Text(text).font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(DLSpace.sm).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dlPanel, in: RoundedRectangle.key)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("im-route-\(route.rawValue)")
    }
}
