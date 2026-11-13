import DLCore
import SwiftUI

/// "Manage Meshtastic" in the Chat drawer, shared by the Public and Nodes sections: the radio's status,
/// its channels (mute or hide), the radios it has heard (mute, ignore, forget), and history. Every choice
/// here is phone-side: nothing is ever written to the radio's channels or node list.
struct MeshManageView: View {
    let mesh: MeshtasticModel
    let done: () -> Void
    private var prefs: MeshPrefs { MeshPrefs.shared }
    @State private var forgetting: MeshNode?

    private var radios: [MeshNode] {
        mesh.nodes.values.filter { $0.source == .radio }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if mesh.status == .ready, !mesh.privacyNoteSeen {
                    Section { RadioPrivacyNote(mesh: mesh).listRowBackground(Color.dlNight).listRowInsets(EdgeInsets()) }
                }
                Section {
                    NavigationLink { MeshRadioSettingsView(mesh: mesh) } label: {
                        HStack(spacing: DLSpace.sm) {
                            Image(systemName: "slider.horizontal.3").font(.dl(.title3)).foregroundStyle(Color.dlSoft).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Radio settings").font(.dl(.headline)).foregroundStyle(Color.dlText)
                                Text("Power, hops, name, role, location and more").font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                            }
                        }
                        .frame(minHeight: DLSize.control)
                    }
                    .disabled(!mesh.canChangeSettings)
                    .listRowBackground(Color.dlNight).accessibilityIdentifier("mesh-settings")
                } footer: {
                    footer(mesh.canChangeSettings
                           ? "Written to your radio, which restarts for a moment. Shown as usable only for a radio you confirmed is yours."
                           : mesh.settingsBlocker ?? "")
                }

                Section {
                    Text(MeshStatus.text(mesh)).font(.dl(.subheadline)).foregroundStyle(Color.dlText)
                        .listRowBackground(Color.dlNight).accessibilityIdentifier("mesh-manage-status")
                    if !mesh.isOn {
                        Text("Meshtastic is off. Turn it on in Settings, after the radio notice, to see channels and radios.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
                    }
                } header: { header("Radio") }

                Section {
                    if mesh.channels.isEmpty {
                        note("Your radio's channels appear here once it connects.")
                    }
                    ForEach(mesh.channels) { channel in channelRow(channel) }
                } header: { header("Channels") } footer: {
                    footer("Mute stops badges for a channel. Hide takes it out of Chat. Both only change this phone; the radio's channels are never touched.")
                }

                Section {
                    if radios.isEmpty { note("No other radios heard yet.") }
                    ForEach(radios) { node in nodeRow(node) }
                } header: { header("Radios heard") } footer: {
                    footer("Mute stops badges. Ignore hides a radio and drops its messages. Forget clears it and its chat from this phone; it comes back when your radio next announces it. The radio's own node list is not changed.")
                }

                Section {
                    NavigationLink { MeshHistoryView(mesh: mesh) } label: {
                        HStack(spacing: DLSpace.sm) {
                            Image(systemName: "chart.bar").font(.dl(.title3)).foregroundStyle(Color.dlSoft).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("History and activity").font(.dl(.headline)).foregroundStyle(Color.dlText)
                                Text("Kept " + MeshHistoryView.phrase(mesh.keep) + " · messages per hour and day")
                                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                            }
                        }
                        .frame(minHeight: DLSize.control)
                    }
                    .listRowBackground(Color.dlNight).accessibilityIdentifier("mesh-history")
                }
            }
            .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
            .background(Color.dlNight)
            .navigationTitle("Meshtastic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); done() }.accessibilityIdentifier("manage-mesh-done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Forget \(forgetting?.displayName ?? "this radio")?",
                            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { node in
            Button("Forget and erase chat", role: .destructive) { mesh.forget(node.num); Haptics.success() }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Erases your chat with this radio from this phone. The radio's own node list is not changed.")
        }
    }

    private func channelRow(_ channel: Meshtastic.ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(channel.title(preset: mesh.presetName)).font(.dl(.headline)).foregroundStyle(Color.dlText)
                .padding(.top, DLSpace.xs)
            Text(channel.keyIsPublic ? "Public channel" : "Shared-key channel").font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
            Toggle("Mute", isOn: Binding(get: { prefs.mutedChannels.contains(channel.index) },
                                         set: { Haptics.tap(); prefs.setMuted($0, channel: channel.index) }))
                .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-mute-channel-\(channel.index)")
            Toggle("Hide from Chat", isOn: Binding(get: { prefs.hiddenChannels.contains(channel.index) },
                                                   set: { Haptics.tap(); prefs.setHidden($0, channel: channel.index) }))
                .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-hide-channel-\(channel.index)")
        }
        .font(.dl(.body)).tint(Color.dlGo)
        .listRowBackground(Color.dlNight)
    }

    private func nodeRow(_ node: MeshNode) -> some View {
        let muted = prefs.mutedNodes.contains(node.num), ignored = prefs.ignoredNodes.contains(node.num)
        return HStack(spacing: DLSpace.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName).font(.dl(.headline)).foregroundStyle(Color.dlText)
                if ignored || muted {
                    Text(ignored ? "Ignored" : "Muted").font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { Haptics.tap(); prefs.setMuted(!muted, node: node.num) } label: {
                    Label(muted ? "Unmute" : "Mute", systemImage: muted ? "bell" : "bell.slash")
                }
                Button { Haptics.tap(); prefs.setIgnored(!ignored, node: node.num) } label: {
                    Label(ignored ? "Stop ignoring" : "Ignore", systemImage: ignored ? "eye" : "eye.slash")
                }
                Button(role: .destructive) { Haptics.tap(); forgetting = node } label: { Label("Forget", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.dl(.title3)).foregroundStyle(Color.dlSoft)
                    .frame(width: DLSize.control, height: DLSize.control).contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(node.displayName)").accessibilityIdentifier("mesh-node-menu-\(node.num)")
        }
        .frame(minHeight: DLSize.control)
        .listRowBackground(Color.dlNight)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { forgetting = node } label: { Label("Forget", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { prefs.setMuted(!muted, node: node.num) } label: { Label(muted ? "Unmute" : "Mute", systemImage: "bell.slash") }.tint(Color.dlGo)
        }
        .accessibilityAction(named: muted ? "Unmute" : "Mute") { prefs.setMuted(!muted, node: node.num) }
        .accessibilityAction(named: ignored ? "Stop ignoring" : "Ignore") { prefs.setIgnored(!ignored, node: node.num) }
        .accessibilityAction(named: "Forget") { forgetting = node }
    }

    private func header(_ text: String) -> some View { Text(text).font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft) }
    private func footer(_ text: String) -> some View { Text(text).font(.dl(.footnote)).foregroundStyle(Color.dlSoft) }
    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
    }
}
