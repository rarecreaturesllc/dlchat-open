/// One wording for the radio's state, shared by Chat and Settings.
enum MeshStatus {
    @MainActor
    static func text(_ mesh: MeshtasticModel) -> String {
        let name = mesh.radioName ?? "the radio"
        if mesh.licensed { return "\(name) is in licensed mode. DLChat will not send through it." }
        if mesh.applying { return "Updating \(name)'s settings. It may restart." }
        if mesh.regionUnset, mesh.status == .ready { return "\(name) has no region yet, so it cannot send. Set it in the Meshtastic app." }
        switch mesh.status {
        case .off: return "Radio off"
        case .bluetoothOff: return "Turn on Bluetooth to use the radio."
        case .unauthorized: return "DLChat needs Bluetooth permission for the radio (iOS Settings > DLChat)."
        case .searching: return "Looking for Meshtastic radios nearby"
        case .connecting: return "Connecting to \(name)"
        case .disconnected: return "\(name) is out of reach, off, or in use by another phone. Reconnecting when it is free."
        case .busy: return "Radio busy: another app on this iPhone, likely Meshtastic, is using \(name). DLChat connects when it lets go."
        case .released: return mesh.letGoByHand ? "Let go of \(name) so another app can use it." : "Let go of \(name) while DLChat was in the background. Taking it back…"
        case .ready:
            _ = mesh.mineVersion
            return mesh.isMine ? "Sending and receiving by radio through \(name)"
                               : "Connected to \(name). If it's yours, confirm it in Settings to unlock its Radio settings."
        }
    }
}
