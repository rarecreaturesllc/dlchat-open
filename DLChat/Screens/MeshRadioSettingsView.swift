import DLCore
import SwiftUI

/// Radio settings, written to the radio the user confirmed is theirs. Each change is one short write and the
/// radio restarts briefly. Region, frequency, duty cycle and channel keys are never offered or written.
struct MeshRadioSettingsView: View {
    let mesh: MeshtasticModel
    @State private var longName = ""
    @State private var shortName = ""
    @State private var pin = ""
    @State private var pendingPreset: UInt64?
    @State private var failed = false
    @State private var shareLocation = false

    private var locked: Bool { !mesh.canChangeSettings }

    var body: some View {
        List {
            if let why = mesh.settingsBlocker {
                note(why).accessibilityIdentifier("mesh-settings-blocker")
            }
            if failed {
                Label("The radio did not take that change. Nothing was changed.", systemImage: "exclamationmark.triangle.fill")
                    .font(.dl(.subheadline, .semibold)).foregroundStyle(Color.dlWarn).listRowBackground(Color.dlNight)
                    .accessibilityIdentifier("mesh-settings-failed")
            }
            section("Transmit power", footer: "Region maximum (0) means the highest level legal where you are, not low power. A number from 1 to 30 dBm caps it lower; the radio still limits it to its own hardware and your region.") {
                Picker("Transmit power", selection: Binding(get: { mesh.txPower ?? 0 }, set: { apply(mesh.setTxPower($0)) })) {
                    Text("Region maximum (0, default)").tag(0)
                    ForEach(1...30, id: \.self) { Text("\($0) dBm").tag($0) }
                }
                .accessibilityIdentifier("mesh-set-txpower")
            }
            section("Hop limit", footer: "How many radios may pass your messages on. Default 3. 7 adds airtime and congestion on a busy public mesh, for everyone.") {
                Stepper("Hops: \(mesh.hopLimit ?? 3)", value: Binding(get: { mesh.hopLimit ?? 3 }, set: { apply(mesh.setHopLimit($0)) }), in: 1...7)
                    .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-set-hops")
            }
            section("Radio name", footer: "Long name up to \(Meshtastic.maxLongName) bytes, short name up to \(Meshtastic.maxShortName). Everyone on the mesh sees them.") {
                TextField("Long name", text: $longName).autocorrectionDisabled().accessibilityIdentifier("mesh-set-longname")
                TextField("Short name", text: $shortName).autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .accessibilityIdentifier("mesh-set-shortname")
                Button("Save name") { apply(mesh.setRadioName(long: longName, short: shortName)) }
                    .disabled(locked || longName.trimmingCharacters(in: .whitespaces).isEmpty || shortName.trimmingCharacters(in: .whitespaces).isEmpty
                              || longName.utf8.count > Meshtastic.maxLongName || shortName.utf8.count > Meshtastic.maxShortName)
                    .accessibilityIdentifier("mesh-set-name-save")
            }
            section("Role", footer: "Client relays and shows up in the node list. Client Mute stays quiet and does not relay. Tracker is for a radio that reports its position.") {
                Picker("Role", selection: Binding(get: { mesh.role ?? Meshtastic.Role.client }, set: { apply(mesh.setRole($0)) })) {
                    Text("Client").tag(Meshtastic.Role.client)
                    Text("Client Mute").tag(Meshtastic.Role.clientMute)
                    Text("Tracker").tag(Meshtastic.Role.tracker)
                }
                .accessibilityIdentifier("mesh-set-role")
            }
            section("Location sharing", footer: "Your radio's GPS position goes out to everyone who can hear it. A lower precision shares a wider area. A channel with the public key is capped at about 700 m by the radio.") {
                Toggle("Share my location", isOn: Binding(get: { mesh.sharesLocation }, set: { apply(mesh.setLocationSharing($0)) }))
                    .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-set-location")
            }
            section("Modem preset", footer: "Changing this can stop you hearing the default public channel (LongFast) and other people's radios, until they use the same preset. Only change it if everyone you want to reach does too.") {
                Picker("Preset", selection: Binding(get: { mesh.modemPreset ?? 0 }, set: { pendingPreset = $0 })) {
                    ForEach(Meshtastic.modemPresets, id: \.code) { Text($0.name).tag($0.code) }
                }
                .accessibilityIdentifier("mesh-set-preset")
            }
            section("Bluetooth PIN", footer: "Six digits, not starting with 0. After a change iOS must forget the radio (iOS Settings > Bluetooth) and pair again.") {
                SecureField("New 6-digit PIN", text: $pin).keyboardType(.numberPad).autocorrectionDisabled()
                    .accessibilityIdentifier("mesh-set-pin")
                Button("Set fixed PIN") { if let n = UInt32(pin) { apply(mesh.setBluetoothPIN(n)); pin = "" } }
                    .disabled(locked || pin.count != 6 || pin.first == "0" || UInt32(pin) == nil)
                    .accessibilityIdentifier("mesh-set-pin-save")
            }
            section("Power saving", footer: mesh.role == Meshtastic.Role.tracker
                    ? "Sleeps Bluetooth and the radio between reports, so DLChat will lose the connection. Only for a stand-alone tracker."
                    : "On a T-Echo and similar radios this only works in the Tracker role, so it is off the table until you pick that role.") {
                Toggle("Power saving", isOn: Binding(get: { mesh.powerSaving ?? false }, set: { apply(mesh.setPowerSaving($0)) }))
                    // Turning it off is always allowed, so it can never get stuck on after a role change.
                    .disabled(locked || (mesh.role != Meshtastic.Role.tracker && mesh.powerSaving != true)).frame(minHeight: DLSize.control)
                    .accessibilityIdentifier("mesh-set-powersaving")
            }
            section("Relay mode", footer: "Which messages this radio passes on. All is the normal choice. None is only for the Tracker role.") {
                Picker("Relay mode", selection: Binding(get: { mesh.rebroadcastMode ?? Meshtastic.Rebroadcast.all }, set: { apply(mesh.setRebroadcastMode($0)) })) {
                    Text("All").tag(Meshtastic.Rebroadcast.all)
                    Text("Local only").tag(Meshtastic.Rebroadcast.localOnly)
                    Text("Known radios only").tag(Meshtastic.Rebroadcast.knownOnly)
                    Text("Core messages only").tag(Meshtastic.Rebroadcast.corePortnumsOnly)
                    if mesh.role == Meshtastic.Role.tracker { Text("None").tag(Meshtastic.Rebroadcast.none) }
                }
                .accessibilityIdentifier("mesh-set-relay")
            }
            section("Internet bridge (MQTT)", footer: "\"OK to share\" is only a request: gateways running official firmware honour it on channels with the default key. It is off unless someone turned it on. \"Ignore\" drops messages that came to you through an internet bridge.") {
                let mqtt = mesh.mqtt ?? (okToMQTT: false, ignoreMQTT: false)
                Toggle("OK to share my messages to internet bridges", isOn: Binding(get: { mqtt.okToMQTT }, set: { apply(mesh.setMQTT(okToMQTT: $0, ignoreMQTT: mqtt.ignoreMQTT)) }))
                    .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-set-oktomqtt")
                Toggle("Ignore messages from internet bridges", isOn: Binding(get: { mqtt.ignoreMQTT }, set: { apply(mesh.setMQTT(okToMQTT: mqtt.okToMQTT, ignoreMQTT: $0)) }))
                    .frame(minHeight: DLSize.control).accessibilityIdentifier("mesh-set-ignoremqtt")
            }
        }
        .tint(Color.dlGo).disabled(locked)
        .listStyle(.grouped).listRowSeparatorTint(Color.dlHairline).scrollContentBackground(.hidden)
        .background(Color.dlNight)
        .navigationTitle("Radio settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { longName = mesh.radioName ?? ""; shortName = mesh.shortName ?? "" }
        .confirmationDialog("Change the modem preset?", isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
                            titleVisibility: .visible) {
            Button("Change preset", role: .destructive) { if let p = pendingPreset { apply(mesh.setModemPreset(p)) }; pendingPreset = nil }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: {
            Text("You may stop hearing LongFast and other people's radios until they use the same preset. The channel name and frequency slot can change with it.")
        }
    }

    private func apply(_ ok: Bool) { failed = !ok; if ok { Haptics.success() } else { Haptics.error() } }

    private func section<C: View>(_ title: String, footer: String, @ViewBuilder _ content: () -> C) -> some View {
        Section {
            content().font(.dl(.body)).foregroundStyle(Color.dlText).listRowBackground(Color.dlNight)
        } header: {
            Text(title).font(.dl(.footnote, .semibold)).foregroundStyle(Color.dlSoft)
        } footer: {
            Text(footer).font(.dl(.footnote)).foregroundStyle(Color.dlSoft)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dl(.subheadline)).foregroundStyle(Color.dlSoft).listRowBackground(Color.dlNight)
    }
}
