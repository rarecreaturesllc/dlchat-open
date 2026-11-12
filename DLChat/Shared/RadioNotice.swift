import Foundation

/// The radio-rules notice (blueprint section 13). Shown once, before the first use of sound over a
/// radio, and always readable again from the Safety sheet. It states the risk and claims nothing is
/// legal, approved or certified. Whether it has been shown is a plain flag: it holds no secret.
enum RadioNotice {
    static let defaultsKey = "radioNoticeSeen"

    static let title = "Before you use a radio"

    static let paragraphs = [
        "Radio rules differ by country and by service. In the United States, GMRS rules prohibit coded messages or messages with hidden meanings, and amateur radio rules prohibit messages encoded to obscure their meaning, apart from a narrow exception for emergencies when normal systems are down.",
        "DLChat messages are encrypted. Sending them over a radio may be prohibited outside a real emergency, depending on the radio service and where you are.",
        "DLChat does not transmit anything itself. You hold the radio and you are responsible for how you use it. This is not legal advice, and DLChat is not approved or certified by any radio regulator.",
        "QR codes and copy and paste do not use a radio. The practice drill uses none of them.",
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
