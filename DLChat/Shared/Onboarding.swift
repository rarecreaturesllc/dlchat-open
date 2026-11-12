import Foundation

/// First-run setup after the PIN: "Create a group for friends or family?", asked once. Whether it has been
/// answered is a plain flag with no secret in it. A wipe clears it, so the next setup asks again.
enum Onboarding {
    static let defaultsKey = "onboarding.done"

    static func done(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func markDone(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Asked only with no group on this phone and the question not yet answered. Someone updating with
    /// groups already saved never sees it.
    static func shouldAsk(hasGroups: Bool, defaults: UserDefaults = .standard) -> Bool {
        !hasGroups && !done(defaults)
    }
}
