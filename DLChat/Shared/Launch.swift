import Foundation

extension Array where Element == String {
    func chunked(_ n: Int) -> [[String]] {
        stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) }
    }
}

enum Screen: String, Hashable, CaseIterable {
    case create, compose, readout, decode, qr, scan, tones, listen, practice, radio, notice, settings, groups, chat, safety, meshmap
}

/// Launch argument for repeatable screenshots: `-screen create|compose|readout|decode|qr|scan|tones|listen|practice|radio|notice|settings|groups|chat|safety|meshmap`.
/// `practice`, `radio` and `settings` open Settings with the drill or the rules on top; `notice` is the same as `radio`.
struct Launch {
    let screen: Screen?
    init(_ args: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ k: String) -> String? { args.firstIndex(of: k).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        screen = value("-screen").flatMap(Screen.init(rawValue:))
    }
}
