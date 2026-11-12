import DLCore
import SwiftUI
import UIKit

/// "Manage groups" in the Chat drawer: choose the active group, reorder, remove, and open a group's phrase
/// and rooms. Create and join live here too, so this is the one place groups are managed. Below the groups, the
/// Meshtastic section opens the radio's own channels and direct messages in Chat.
struct GroupListView: View {
    let groups: GroupModel
    let mesh: MeshtasticModel
    /// Shows a Meshtastic conversation in Chat and closes this screen.
    let openMesh: (MeshConversation) -> Void
    let done: () -> Void
    @State private var showingNodes = false
    @State private var showingHistory = false
    @State private var creating = false
    @State private var removing: ChatGroup?
    @State private var removeFailed = false
    @State private var editing: EditMode = .inactive
    @State private var detailID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let removeNote = "Erases this group's phrase, key and received messages from this phone. You can only join again with the phrase on paper."

    var body: some View {
        NavigationStack {
            List {
                if groups.groups.isEmpty {
                    Section {
                        Text("No groups yet. Create one and share its words in person, or join with a phrase you were given.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft)
                            .listRowBackground(Color.dlNight)
                    }
                } else {
                    Section {
                        ForEach(groups.groups) { group in row(group) }
                            .onMove { groups.move(from: $0, to: $1); Haptics.tap() }
                    } footer: {
                        Text(mesh.open == nil ? "Send, History and rooms use the group with the check mark."
                                          : "Send, History and rooms use the group with the check mark. Tap it to show its chat again.")
                            .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                    }
                }
                if removeFailed {
                    Label("The group could not be removed. Its keys are still on this phone.", systemImage: "exclamationmark.triangle.fill")
                        .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn)
                        .listRowBackground(Color.dlNight).accessibilityIdentifier("remove-failed")
                }
                Section {
                    Button { Haptics.tap(); creating = true } label: {
                        Label("Create or join a group", systemImage: "plus.square.fill")
                            .font(.dl(.headline)).foregroundStyle(Color.dlGo).frame(minHeight: DLSize.control)
                    }
                    .listRowBackground(Color.dlNight).accessibilityIdentifier("add-group")
                }
                if !groups.groups.isEmpty {
                    MeshSection(mesh: mesh, openChat: openMesh, showNodes: { showingNodes = true }, showHistory: { showingHistory = true })
                }
            }
            .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
            .background(Color.dlNight)
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if groups.groups.count > 1 { EditButton().accessibilityIdentifier("reorder-groups") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { Haptics.tap(); done() }.accessibilityIdentifier("groups-done") }
            }
            .environment(\.editMode, $editing)
            .navigationDestination(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
                if let detailID { GroupDetailView(groups: groups, groupID: detailID) }
            }
            .navigationDestination(isPresented: $showingNodes) { MeshNodeListView(mesh: mesh, openChat: openMesh) }
            .navigationDestination(isPresented: $showingHistory) { MeshHistoryView(mesh: mesh) }
            .confirmationDialog(
                "Remove \(removing?.name ?? "group")?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible, presenting: removing
            ) { group in
                Button("Remove and erase", role: .destructive) { remove(group) }
                Button("Cancel", role: .cancel) { Haptics.tap() }
            } message: { _ in
                Text(Self.removeNote)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $creating) { GroupSetupView(model: groups) { creating = false } }
    }

    private func row(_ group: ChatGroup) -> some View {
        let active = group.id == groups.activeGroup?.id
        return HStack(spacing: DLSpace.xs) {
            Button { choose(group) } label: {
                HStack(spacing: DLSpace.sm) {
                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                        .font(.dl(.title2)).foregroundStyle(active ? Color.dlGo : Color.dlSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.dl(.headline)).foregroundStyle(Color.dlText)
                        Text(summary(group)).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DLSize.control).contentShape(Rectangle())
            }
            .accessibilityLabel(active ? "\(group.name), active group" : "Make \(group.name) the active group")
            .accessibilityIdentifier("choose-\(group.name)")
            Button { Haptics.tap(); detailID = group.id } label: {
                Image(systemName: "info.circle").font(.dl(.title3)).foregroundStyle(Color.dlSoft)
                    .frame(width: DLSize.control, height: DLSize.control)
            }
            .accessibilityLabel("Details for \(group.name)")
            .accessibilityIdentifier("details-\(group.name)")
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.dlNight)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !active { Button { choose(group) } label: { Label("Use", systemImage: "checkmark.circle") }.tint(Color.dlGo) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { Haptics.tap(); removing = group } label: { Label("Remove", systemImage: "trash") }
        }
        .contextMenu {
            if !active { Button { choose(group) } label: { Label("Use this group", systemImage: "checkmark.circle") } }
            Button(role: .destructive) { Haptics.tap(); removing = group } label: { Label("Remove group", systemImage: "trash") }
        }
        .accessibilityAction(named: "Remove group") { removing = group }
        .accessibilityAction(named: "Move up") { shift(group, by: -1) }
        .accessibilityAction(named: "Move down") { shift(group, by: 1) }
    }

    private func summary(_ group: ChatGroup) -> String {
        let rooms = group.rooms.count
        return "\(group.wordCount) words" + (rooms == 0 ? "" : " · \(rooms) room" + (rooms == 1 ? "" : "s"))
    }

    private func choose(_ group: ChatGroup) {
        mesh.openConversation(nil)  // Chat goes back to the group's own chat
        guard group.id != groups.activeGroup?.id else { return }
        groups.setActive(group)
        Haptics.select()
    }

    private func shift(_ group: ChatGroup, by step: Int) {
        guard let i = groups.groups.firstIndex(of: group) else { return }
        let j = i + step
        guard groups.groups.indices.contains(j) else { return }
        groups.move(from: IndexSet(integer: i), to: step > 0 ? j + 1 : j)
    }

    private func remove(_ group: ChatGroup) {
        // The row leaves and the gap closes; a failure is said in words above, never hidden by the motion.
        withAnimation(reduceMotion ? nil : DLMotion.exit) { removeFailed = !groups.remove(group) }
        if removeFailed { Haptics.error() } else { Haptics.success() }
    }
}

/// One group: its phrase and safety words behind a hold, its rooms, and removal.
struct GroupDetailView: View {
    let groups: GroupModel
    let groupID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var newRoom = ""
    @State private var confirming = false
    @State private var removeFailed = false
    @FocusState private var roomFocused: Bool
    @State private var pictureFor: Phrase?
    @State private var checking = false

    var body: some View {
        if let group = groups.groups.first(where: { $0.id == groupID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: DLSpace.md) {
                    if let phrase = groups.phrase(of: group) {
                        HoldToReveal(title: "Hold to see the phrase and safety words") {
                            VStack(alignment: .leading, spacing: DLSpace.sm) {
                                Text(phrase).font(.dl(.title3, .bold)).foregroundStyle(Color.dlText)
                                    .accessibilityIdentifier("group-phrase")
                                Text(groups.safetyWords(of: group).joined(separator: " · "))
                                    .font(.dl(.title2, .bold)).foregroundStyle(Color.dlText)
                                Text("Safety words. Everyone's phone should show these same three.")
                                    .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                            }
                            .padding(DLSpace.md).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.dlPanel, in: RoundedRectangle.key)
                        }
                        HoldToShowPhrase(phrase: GroupInvite(phrase: phrase, name: group.name).url.absoluteString)
                        Button("Check my written copy") { checking = true }
                            .buttonStyle(.dlSecondary).accessibilityIdentifier("open-backup-check")
                            .sheet(isPresented: $checking) { BackupCheckView(phrase: phrase) { checking = false } }
                        if let parsed = try? Phrase.parse(phrase) {
                            Button("Make a picture invite") { pictureFor = parsed }
                                .buttonStyle(.dlSecondary).accessibilityIdentifier("make-picture")
                                .sheet(isPresented: Binding(get: { pictureFor != nil }, set: { if !$0 { pictureFor = nil } })) {
                                    if let pictureFor { PictureInviteView(phrase: pictureFor, name: group.name, safetyWords: groups.safetyWords(of: group)) { self.pictureFor = nil } }
                                }
                        }
                    } else {
                        Text("This group's phrase is missing from the Keychain. Remove it and join again.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlWarn)
                    }

                    DLLegend("Rooms")
                    Text((["Main"] + group.rooms).joined(separator: ", ")).font(.dl(.body)).foregroundStyle(Color.dlText)
                    TextField("New room word", text: $newRoom)
                        .focused($roomFocused).submitLabel(.done)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(addRoom).dlField(focused: roomFocused) { roomFocused = true }
                        .accessibilityIdentifier("group-room-field")
                    Button("Add room", action: addRoom).buttonStyle(.dlSecondary)
                        .disabled(newRoom.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("group-add-room")
                    Text("Rooms keep the group's chats apart. They are not secret from the group: anyone with the phrase who guesses a room word can read that room.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)

                    DLLegend("Read receipts")
                    Toggle("Send and see read receipts", isOn: Binding(get: { groups.receiptGroups.contains(group.id) },
                                                                      set: { Haptics.tap(); groups.setReceipts($0, for: group) }))
                        .font(.dl(.body)).foregroundStyle(Color.dlText).tint(Color.dlGo).frame(minHeight: DLSize.control)
                        .accessibilityIdentifier("group-read-receipts")
                    Text("Off unless you turn it on, and only for this group. Both ways or not at all: with it on, your phone tells the group which messages you've seen in Chat, and your messages show \"Read by\" counting others who turned it on too. People with it off never send or see any. It shows when you're using DLChat, and each receipt is one more sealed post on the relays and, with the radio on, one more radio transmission. Encrypted words and sounds aren't reported: \"Decrypted\" covers those.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft).fixedSize(horizontal: false, vertical: true)

                    if removeFailed {
                        Text("The group could not be removed. Its keys are still on this phone.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlWarn)
                    }
                    Button("Remove this group") { confirming = true }
                        .buttonStyle(.dlDanger).padding(.top, DLSpace.md).accessibilityIdentifier("remove-group")
                }
                .padding(DLSpace.md)
                .contentShape(Rectangle()).onTapGesture { roomFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.dlNight)
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove \(group.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Remove and erase", role: .destructive) { Haptics.tap(); if groups.remove(group) { dismiss() } else { removeFailed = true } }
                Button("Cancel", role: .cancel) { Haptics.tap() }
            } message: {
                Text("Erases this group's phrase, key and received messages from this phone. You can only join again with the phrase on paper.")
            }
        } else {
            Color.dlNight
        }
    }

    private func addRoom() {
        guard let group = groups.groups.first(where: { $0.id == groupID }) else { return }
        groups.addRoom(newRoom, to: group)
        newRoom = ""
        roomFocused = false
    }
}
