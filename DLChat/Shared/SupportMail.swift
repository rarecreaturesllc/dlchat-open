import UIKit

/// Settings → "Send Debug Logs to support@rarecreatures.app": a draft in the user's own email app with what they
/// typed, DLChat's version and the phone model and iOS version. Never messages, groups, phrases, keys, relays or
/// radio details, and no system log (it can hold device and network identifiers). DLChat sends nothing itself;
/// the user reads the draft and taps Send.
enum SupportMail {
    static let address = "support@rarecreatures.app"

    /// Opens the draft. If no email app opens, copies it (expiring, this device only) and returns false.
    @MainActor static func send(problem: String) async -> Bool {
        let text = body(problem: problem)
        if let url = url(body: text), await UIApplication.shared.open(url) { return true }
        Hygiene.copyPlaintext(text)
        return false
    }

    static func body(problem: String) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var sys = utsname()
        uname(&sys)
        let model = withUnsafeBytes(of: sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return [
            problem.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "--- Debug logs (you can edit or delete anything below) ---",
            "App: DLChat \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
            "Device: \(model), iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "Language: \(Locale.current.identifier)",
        ].joined(separator: "\n")
    }

    static func url(body: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        return URL(string: "mailto:\(address)?subject=\(encode("DLChat debug logs"))&body=\(encode(body))")
    }
}
