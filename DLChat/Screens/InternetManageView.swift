import DLCore
import SwiftUI

/// "Manage Internet Messages" in the Chat drawer: add a contact, rename or remove the ones you have,
/// and reach the relay settings. Names are only ever shown on this phone.
struct InternetManageView: View {
    let direct: DirectModel
    /// A contact was just added and its chat should open: Chat shows it and this screen closes.
    let openChat: (UUID) -> Void
    let done: () -> Void
    @State private var adding = false
    @State private var showingRelays = false
    @State private var renaming: DirectContact?
    @State private var newName = ""
    @State private var removing: DirectContact?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { Haptics.tap(); adding = true } label: {
                        Label("Add a contact", systemImage: "plus.square.fill")
                            .font(.dl(.headline)).foregroundStyle(Color.dlGo).frame(minHeight: DLSize.control)
                    }
                    .listRowBackground(Color.dlNight).accessibilityIdentifier("manage-add-contact")
                }
                Section {
                    if direct.contacts.isEmpty {
                        Text("No contacts yet. Add one in person with a QR code, or send a one-time invite link.")
                            .font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
                    }
                    ForEach(direct.contacts) { contact in row(contact) }
                } header: {
                    Text("Contacts").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
                } footer: {
                    Text("Names are only shown on this phone. Removing a contact erases its keys and messages here.")
                        .font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
                }
                Section {
                    Button { Haptics.tap(); showingRelays = true } label: {
                        HStack {
                            Label("Relays and delivery", systemImage: "network").font(.dl(.headline)).foregroundStyle(Color.dlText)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
                        }
                        .frame(minHeight: DLSize.control).contentShape(Rectangle())
                    }
                    .listRowBackground(Color.dlNight).accessibilityIdentifier("manage-relays")
                }
            }
            .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
            .background(Color.dlNight)
            .navigationTitle("Internet Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); done() }.accessibilityIdentifier("manage-direct-done")
                }
            }
            .alert("Rename contact", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName).autocorrectionDisabled()
                Button("Save") { if let renaming { direct.rename(renaming.id, to: newName); Haptics.success() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only you see this name.")
            }
            .confirmationDialog("Remove \(removing?.name ?? "contact")?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { contact in
                Button("Remove and erase", role: .destructive) { direct.remove(contact.id); Haptics.success() }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Erases this contact's keys and messages from this phone. To talk again you need a new invite.")
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $adding) {
            AddContactView(direct: direct, incoming: nil, openChat: { id in adding = false; openChat(id) }) { adding = false }
        }
        .sheet(isPresented: $showingRelays) { InternetMessagingSettingsView(direct: direct) { showingRelays = false } }
    }

    private func row(_ contact: DirectContact) -> some View {
        HStack(spacing: DLSpace.xs) {
            Image(systemName: "lock.fill").font(.dl(.title3)).foregroundStyle(Color.dlSoft).frame(width: 28).accessibilityHidden(true)
            Text(contact.name).font(.dl(.headline)).foregroundStyle(Color.dlText)
            Spacer(minLength: 0)
            // The visible way to what the swipe and long press also offer.
            Menu {
                Button { startRename(contact) } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { removing = contact } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.dl(.title3)).foregroundStyle(Color.dlSoft)
                    .frame(width: DLSize.control, height: DLSize.control).contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(contact.name)").accessibilityIdentifier("manage-contact-menu-\(contact.name)")
        }
        .frame(minHeight: DLSize.control)
        .listRowBackground(Color.dlNight)
        .swipeActions(edge: .leading) { Button { startRename(contact) } label: { Label("Rename", systemImage: "pencil") }.tint(Color.dlGo) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { removing = contact } label: { Label("Remove", systemImage: "trash") }
        }
        .contextMenu {
            Button { startRename(contact) } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { removing = contact } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityAction(named: "Rename") { startRename(contact) }
        .accessibilityAction(named: "Remove") { removing = contact }
    }

    private func startRename(_ contact: DirectContact) { Haptics.tap(); newName = contact.name; renaming = contact }
}
