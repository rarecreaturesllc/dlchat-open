import DLCore
import SwiftUI
import UIKit

/// What Chat shows: one conversation, or (nil) the drawer listing all of them.
enum ChatSelection: Hashable {
    case group(UUID)
    case direct(UUID)
    case mesh(MeshConversation)
}

/// The Chat tab's drawer: every conversation, in four sections, each with a plain privacy label.
/// DL Group Chats (picture-invite and phrase groups), Internet Messages (one-to-one with anyone who has
/// DLChat), Meshtastic Public (the radio's channels) and Meshtastic Nodes (direct messages to radios).
struct ChatDrawerView: View {
    let groups: GroupModel
    let direct: DirectModel
    let mesh: MeshtasticModel
    let open: (ChatSelection) -> Void
    let newGroup: () -> Void
    /// Opens the group list: choose the active group, reorder, remove, see a phrase.
    let manageGroups: () -> Void
    let addContact: () -> Void
    @State private var showingNodes = false
    @AppStorage("drawer.collapsed") private var collapsedRaw = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    private func toggle(_ section: String) {
        var set = collapsed
        if set.contains(section) { set.remove(section) } else { set.insert(section) }
        withAnimation(reduceMotion ? nil : DLMotion.move) { collapsedRaw = set.sorted().joined(separator: ",") }
        Haptics.tap()
    }

    var body: some View {
        NavigationStack {
            List {
                section("groups", title: "DL Group Chats", count: groups.groups.count,
                        label: "Only people with your group's picture and password, or its phrase, can read these.",
                        manage: groups.groups.isEmpty ? nil : manageGroups) {
                    if groups.groups.isEmpty {
                        note("No groups yet.")
                    }
                    ForEach(groups.groups) { group in
                        row(icon: "person.3.fill", title: group.name, subtitle: "\(group.wordCount)-word phrase", unread: 0) {
                            open(.group(group.id))
                        }
                        .accessibilityIdentifier("drawer-group-\(group.name)")
                    }
                    addRow("New group (picture invite)", id: "drawer-new-group", action: newGroup)
                }

                section("direct", title: "Internet Messages", count: direct.contacts.count,
                        label: "End-to-end encrypted with post-quantum keys, sent only over Tor. No phone number or account.") {
                    if direct.contacts.isEmpty {
                        note("Chat one-to-one with anyone who has DLChat. Add them in person with a QR code, or send a one-time invite link.")
                    }
                    ForEach(direct.contacts) { contact in
                        row(icon: "lock.fill", title: contact.name, subtitle: subtitle(contact), unread: direct.unread(contact.id)) {
                            open(.direct(contact.id))
                        }
                        .accessibilityIdentifier("drawer-contact-\(contact.name)")
                    }
                    addRow("Add a contact", id: "drawer-add-contact", action: addContact)
                }

                section("public", title: "Meshtastic Public", count: mesh.channels.count,
                        label: "Public: anyone with a Meshtastic radio nearby can read these.", warn: true) {
                    if !mesh.isOn {
                        note("Turn on the Meshtastic radio in Settings to see its channels.")
                    } else if mesh.channels.isEmpty {
                        note("Your radio's channels appear here once it connects.")
                    } else {
                        ForEach(mesh.channels) { channel in
                            row(icon: "antenna.radiowaves.left.and.right", title: channel.title(preset: mesh.presetName),
                                subtitle: channel.keyIsPublic ? "Public channel" : "Shared-key channel",
                                unread: mesh.unread[.channel(channel.index)] ?? 0) {
                                open(.mesh(.channel(channel.index)))
                            }
                            .accessibilityIdentifier("drawer-channel-\(channel.index)")
                        }
                    }
                }

                section("nodes", title: "Meshtastic Nodes", count: mesh.directNodes.count,
                        label: "Encrypted to that radio's key, but radio names and who talks to whom are visible on air.") {
                    if !mesh.isOn {
                        note("Turn on the Meshtastic radio in Settings to message other radios.")
                    } else {
                        let heard = mesh.directNodes.count
                        row(icon: "person.2.wave.2", title: "Radios heard",
                            subtitle: heard == 0 ? "No other radios heard yet" : "\(heard) \(heard == 1 ? "radio" : "radios")",
                            unread: mesh.unreadDirect, chevron: true) { showingNodes = true }
                            .accessibilityIdentifier("drawer-nodes")
                    }
                }
            }
            .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
            .background(Color.dlNight)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingNodes) {
                MeshNodeListView(mesh: mesh) { conversation in showingNodes = false; open(.mesh(conversation)) }
            }
        }
        .accessibilityIdentifier("chat-drawer")
    }

    private func subtitle(_ contact: DirectContact) -> String {
        guard let last = direct.lastMessage(contact.id) else { return "Read your safety words to each other once" }
        return (last.outgoing ? "You: " : "") + last.text
    }

    @ViewBuilder
    private func section<Content: View>(_ key: String, title: String, count: Int, label: String, warn: Bool = false,
                                        manage: (() -> Void)? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(key)
        Section {
            if !isCollapsed { content() }
        } header: {
            Button { toggle(key) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
                        if count > 0 { Text("\(count)").font(.dl(.footnote)).foregroundStyle(Color.dlSoft).monospacedDigit() }
                        Spacer()
                        // Keeps room for the Manage key, which lies over this row as its own button.
                        if manage != nil, !typeSize.isAccessibilitySize { manageLabel.hidden() }
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft).frame(width: Self.chevronWidth)
                    }
                    Text(label).font(.dl(.footnote)).foregroundStyle(warn ? Color.dlWarn : Color.dlSoft)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    // At accessibility text sizes the Manage key gets its own line under the label.
                    if manage != nil, typeSize.isAccessibilitySize { manageLabel.hidden() }
                }
                .frame(minHeight: DLSize.control).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .accessibilityLabel("\(title). \(label)")
            .accessibilityHint(isCollapsed ? "Shows this section" : "Hides this section")
            .accessibilityIdentifier("drawer-section-\(key)")
            // Its own button, so it never folds the section, and it stays when the section is folded.
            .overlay(alignment: typeSize.isAccessibilitySize ? .bottomLeading : .topTrailing) {
                if let manage {
                    Button { Haptics.tap(); manage() } label: { manageLabel }
                        .buttonStyle(.dlPress)
                        .padding(.trailing, typeSize.isAccessibilitySize ? 0 : Self.chevronWidth + 8)
                        .accessibilityLabel("Manage groups")
                        .accessibilityIdentifier("drawer-manage-groups")
                }
            }
        }
    }

    private static let chevronWidth: CGFloat = 16

    /// The small, quiet Manage key in the groups header: a 44pt target around a compact legend.
    private var manageLabel: some View {
        Text("MANAGE").dlCaps(.caption).foregroundStyle(Color.dlText)
            .padding(.horizontal, 10).frame(minHeight: 28)
            .overlay { RoundedRectangle.inner.stroke(Color.dlEdge, lineWidth: DLStroke.hair) }
            .frame(minHeight: 44).contentShape(Rectangle())
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addRow(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Label(title, systemImage: "plus.square.fill").font(.dl(.headline)).foregroundStyle(Color.dlGo)
                .frame(minHeight: DLSize.control)
        }
        .listRowBackground(Color.dlNight)
        .accessibilityIdentifier(id)
    }

    private func row(icon: String, title: String, subtitle: String, unread: Int, chevron: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: DLSpace.sm) {
                Image(systemName: icon).font(.dl(.title3)).foregroundStyle(Color.dlSoft).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
                    Text(subtitle).font(.dl(.footnote)).foregroundStyle(Color.dlSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                UnreadBadge(count: unread)
                Image(systemName: "chevron.right").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
                    .opacity(chevron ? 1 : 0.5).accessibilityHidden(true)
            }
            .frame(minHeight: DLSize.control).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.dlNight)
        .accessibilityValue(unread > 0 ? "\(unread) unread" : "")
    }
}

/// The bar above an open conversation: back to the drawer, and the conversation's name.
struct ChatBackBar: View {
    let title: String
    var totalUnread = 0
    let back: () -> Void

    var body: some View {
        // At the largest text sizes the title goes under the back link instead of squeezing it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DLSpace.xs) {
                backLink
                Spacer()
                name.lineLimit(1).fixedSize()
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                backLink
                name.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DLSpace.md)
    }

    private var name: some View {
        Text(title).font(.dl(.headline)).foregroundStyle(Color.dlText)
    }

    private var backLink: some View {
        Button { Haptics.tap(); back() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.dl(.headline))
                Text("Chats").font(.dl(.headline)).lineLimit(1).fixedSize()
                UnreadBadge(count: totalUnread)
            }
            .foregroundStyle(Color.dlText).frame(minHeight: DLSize.control).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(totalUnread > 0 ? "Chats, \(totalUnread) unread" : "Chats")
        .accessibilityIdentifier("chat-back")
    }
}

/// Swipe right from the left edge to go back one level, as a pushed screen does: the conversation
/// follows the finger with the list showing behind it, and on letting go it slides away or settles
/// back. Only a drag that starts in the first points from the edge counts, so swipe to reply and
/// scrolling are left alone. With Reduce Motion the screens swap at once. The "Chats" link is the
/// visible way back.
struct EdgeSwipeBack<Content: View, Behind: View>: View {
    /// How far from the left edge a back swipe may start.
    static var edge: CGFloat { 24 }

    let back: () -> Void
    @ViewBuilder var content: Content
    /// What shows behind while dragging: the screen going back to.
    @ViewBuilder var behind: Behind
    /// Follows the finger; back to zero by itself when the touch ends or is cancelled.
    @GestureState(resetTransaction: Transaction(animation: DLMotion.exit)) private var drag: CGFloat = 0
    /// Let go far enough: the conversation finishes sliding off before the screens swap.
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { geo in
            let offset = leaving ? geo.size.width : drag
            ZStack {
                if offset > 0 { behind.accessibilityHidden(true).allowsHitTesting(false) }
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Down to the screen's bottom edge, under the keyboard too: the frame stops at the
                    // keyboard's top, and the keyboard is see-through, so a background that stopped there
                    // let the Chats list under this conversation show behind the keys.
                    .background(Color.dlNight.ignoresSafeArea())
                    .offset(x: offset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($drag) { value, drag, _ in
                        guard !reduceMotion, starts(value, in: geo.size.width) else { return }
                        drag = max(0, travel(value.translation.width))
                    }
                    .onEnded { value in
                        guard starts(value, in: geo.size.width) else { return }
                        let far = travel(value.translation.width) > geo.size.width / 3
                            || travel(value.predictedEndTranslation.width) > geo.size.width / 2
                        guard far else { return }
                        Haptics.tap()
                        if reduceMotion { back(); return }
                        withAnimation(DLMotion.exit) { leaving = true } completion: { back() }
                    }
            )
        }
    }

    /// Right to left layouts go back from the right edge.
    private func travel(_ dx: CGFloat) -> CGFloat { direction == .rightToLeft ? -dx : dx }

    private func starts(_ value: DragGesture.Value, in width: CGFloat) -> Bool {
        let x = direction == .rightToLeft ? width - value.startLocation.x : value.startLocation.x
        return x < Self.edge && abs(value.translation.width) > abs(value.translation.height)
    }
}
