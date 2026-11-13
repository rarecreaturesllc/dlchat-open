import Foundation

extension Array where Element == String {
    func chunked(_ n: Int) -> [[String]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) }
    }
}

/// Launch arguments for tests, screenshots and timing (`-seed-demo`, `-reset-demo`, `-no-tor`, `-screen`,
/// `-launch-timing` and the rest). They exist only in Debug builds: a release build sees an empty list.
///
/// A release build also drops the settings iOS reads from launch arguments (`-online.tor NO` would
/// otherwise count as a saved setting and turn Tor off), the first time anything asks for the list.
/// `DLChatApp` asks as its first act, before any setting is read.
enum LaunchSwitches {
    static let arguments: [String] = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments
        #else
        UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        return []
        #endif
    }()
}

enum Screen: String, Hashable, CaseIterable {
    case create, compose, readout, decode, qr, scan, tones, listen, practice, radio, notice, settings, groups, chat, safety, meshmap
}

/// Launch argument for repeatable screenshots: `-screen create|compose|readout|decode|qr|scan|tones|listen|practice|radio|notice|settings|groups|chat|safety|meshmap`.
/// `practice`, `radio` and `settings` open Settings with the drill or the rules on top; `notice` is the same as `radio`.
struct Launch {
    let screen: Screen?
    init(_ args: [String] = LaunchSwitches.arguments) {
        func value(_ k: String) -> String? { args.firstIndex(of: k).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        screen = value("-screen").flatMap(Screen.init(rawValue:))
    }
}
