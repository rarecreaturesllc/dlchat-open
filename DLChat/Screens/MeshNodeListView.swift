import DLCore
import SwiftUI

/// The Meshtastic part of the Manage groups screen: the radio's channels, and a way into direct messages.
struct MeshSection: View {
    let mesh: MeshtasticModel
    let openChat: (MeshConversation) -> Void
    let showNodes: () -> Void
    var showHistory: () -> Void = {}

    var body: some View {
        Section {
            if !mesh.isActive {
                note("Turn on the Meshtastic radio in Settings to use its public channel and message other radios.")
            } else if mesh.channels.isEmpty {
                note(mesh.status == .ready ? "Your radio has no channels set." : "Your radio's channels and the radios it hears appear here once it connects.")
            } else {
                ForEach(mesh.channels) { channel in
                    row(icon: "antenna.radiowaves.left.and.right", title: channel.title(preset: mesh.presetName),
                        subtitle: channel.keyIsPublic ? "Public · not private, anyone with a Meshtastic radio can read it"
                                                      : "Shared key · everyone with this channel's key can read it",
                        warn: true, unread: mesh.unread[.channel(channel.index)] ?? 0) {
                        openChat(.channel(channel.index))
                    }
                    .accessibilityIdentifier("mesh-channel-\(channel.index)")
                }
                let heard = mesh.directNodes.count
                row(icon: "person.2.wave.2", title: "Direct messages",
                    subtitle: heard == 0 ? "No other radios heard yet" : "\(heard) \(heard == 1 ? "radio" : "radios") heard · Meshtastic's own encryption",
                    warn: false, unread: mesh.unreadDirect, chevron: true, action: showNodes)
                    .accessibilityIdentifier("mesh-direct")
            }
            // Shown even with the radio off, so how long chats are kept can be set (or erased) at any time.
            row(icon: "chart.bar", title: "History and activity",
                subtitle: "Kept " + MeshHistoryView.phrase(mesh.keep) + " · messages per hour and day",
                warn: false, unread: 0, chevron: true, action: showHistory)
                .accessibilityIdentifier("mesh-history")
        } header: {
            Text("Meshtastic").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
        } footer: {
            Text("Plain Meshtastic messages, so people on the Meshtastic app can read them. They are not sealed with a group's phrase"
                 + (mesh.keep == .off ? " and are not saved." : ". You keep them \(MeshHistoryView.phrase(mesh.keep)), sealed on this iPhone."))
                .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
    }

    private func row(icon: String, title: String, subtitle: String, warn: Bool, unread: Int, chevron: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: DLSpace.sm) {
                Image(systemName: icon).font(.dl(.title3)).foregroundStyle(Color.dlSoft).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
                    Text(subtitle).font(.dl(.footnote)).foregroundStyle(warn ? Color.dlWarn : Color.dlSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                UnreadBadge(count: unread)
                if chevron { Image(systemName: "chevron.right").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft) }
            }
            .frame(minHeight: DLSize.control).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.dlNight)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread > 0 ? "\(unread) unread" : "")
    }
}

/// Every radio this phone's radio has heard, to message one directly. Names are what strangers set on their radios.
struct MeshNodeListView: View {
    let mesh: MeshtasticModel
    let openChat: (MeshConversation) -> Void
    @State private var search = ""

    private var shown: [MeshNode] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return mesh.directNodes }
        return mesh.directNodes.filter { $0.longName.localizedCaseInsensitiveContains(q) || $0.shortName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if mesh.licensed {
                Label("Your radio is in licensed (ham) mode, which does not allow private messages.", systemImage: "exclamationmark.triangle.fill")
                    .font(.dl(.subheadline)).foregroundStyle(Color.dlWarn).listRowBackground(Color.dlNight)
            }
            Section {
                if shown.isEmpty {
                    Text(search.isEmpty ? "No other radios heard yet. They appear as they announce themselves, which can take a few minutes."
                                        : "No radio by that name.")
                        .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
                }
                ForEach(shown) { node in row(node) }
            } footer: {
                Text("Encrypted between the two radios with Meshtastic's own keys (firmware 2.5 or newer), not with your DLChat phrase. Every radio on the mesh can still see who messages whom.")
                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            }
        }
        .searchable(text: $search, prompt: "Name or short name")
        .autocorrectionDisabled()
        .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
        .background(Color.dlNight)
        .navigationTitle("Direct messages")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ node: MeshNode) -> some View {
        let unread = mesh.unread[.direct(node.num)] ?? 0
        return Button { Haptics.tap(); openChat(.direct(node.num)) } label: {
            HStack(spacing: DLSpace.sm) {
                Text(node.shortName.isEmpty ? "?" : node.shortName)
                    .font(.dl(.footnote, .bold)).foregroundStyle(Color.dlNight).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 44, height: 44).background(Color.dlText, in: RoundedRectangle.key)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName).font(.dl(.headline)).foregroundStyle(Color.dlText)
                    Text(detail(node)).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                }
                Spacer(minLength: 0)
                UnreadBadge(count: unread)
            }
            .frame(minHeight: DLSize.control).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.dlNight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message \(node.displayName)")
        .accessibilityValue(unread > 0 ? "\(unread) unread" : "")
        .accessibilityIdentifier("mesh-node-\(node.num)")
    }

    private func detail(_ node: MeshNode) -> String {
        var parts: [String] = []
        if let last = mesh.texts[.direct(node.num)]?.last { parts.append((last.outgoing ? "You: " : "") + last.text) }
        if let hops = node.hops { parts.append(hops == 0 ? "heard directly" : "\(hops) \(hops == 1 ? "hop" : "hops") away") }
        if let heard = node.lastHeard { parts.append("heard " + heard.formatted(.relative(presentation: .named))) }
        if node.publicKey == nil { parts.append("key not known yet") }
        return parts.joined(separator: " · ")
    }
}

struct UnreadBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)").font(.dl(.caption, .bold)).foregroundStyle(Color.dlNight).monospacedDigit()
                .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22).background(Color.dlGo, in: RoundedRectangle.tag)
                .accessibilityHidden(true)
        }
    }
}
