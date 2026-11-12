/// One wording for Tor's state, shared by Chat and Settings.
enum TorStatus {
    @MainActor
    static func text(_ online: OnlineModel) -> String? {
        guard online.torOn else { return nil }
        if online.torFailed { return "Tor could not connect. Nothing is sent until it does." }
        if online.torPort == nil { return "Connecting to Tor (\(online.torProgress)%). Messages wait until it is ready." }
        return "Connected through Tor"
    }
}
