import DLCore
import SwiftUI

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
                Label("Your radio is in licensed mode, which does not allow private messages.", systemImage: "exclamationmark.triangle.fill")
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
        let unread = MeshPrefs.shared.mutedNodes.contains(node.num) ? 0 : mesh.unread[.direct(node.num)] ?? 0
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
