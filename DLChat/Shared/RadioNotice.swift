import Foundation

/// The Meshtastic radio rules notice. Shown, with "I accept", before the radio can be turned on in
/// Settings, and readable again from Settings. It states the risk and claims nothing is legal,
/// approved or certified. Words and sound are for in person and chats, so they have no notice.
/// `seen` is a flag from older builds that showed this before sound; a wipe still clears it.
enum RadioNotice {
    static let defaultsKey = "radioNoticeSeen"

    static let title = "Before you use the Meshtastic radio"

    static let paragraphs = [
        "The Meshtastic radio sends on unlicensed radio bands, such as 902 to 928 MHz in the United States and 868 MHz in Europe. Each country sets its own rules for them, such as power, channels and how often a radio may send.",
        "Encrypted messages may be prohibited on licensed radio services, so DLChat will not send while your radio is set to licensed mode. Only use a radio and region setting that are allowed where you are.",
        "You are responsible for what your radio transmits. This is not legal advice, and DLChat is not approved or certified by any radio regulator.",
    ]

    /// Turning the Meshtastic radio on: the person takes responsibility before it can start.
    static let radioOnAcceptance = "DLChat is free, open source software provided as is, with no warranty. By turning the radio on you confirm that you know the laws for your radio, band and country, that you will follow them, and that you alone are responsible for what you transmit."
    static let radioOnButton = "I accept, turn the radio on"

    static func seen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
