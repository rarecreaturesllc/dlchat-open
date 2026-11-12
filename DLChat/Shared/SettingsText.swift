import Foundation

/// Plain-language copy for Settings, and the message export. No legal entity, contact or hosted URL
/// exists yet (launch blockers 4 and 7), so none is named here. Nothing below claims legal review.
enum SettingsText {
    static let protectedList = [
        "Messages in Chat and History are sealed on this phone and excluded from backups. What you type in Send and Receive is kept in memory only: closing the app, or a crash, erases it.",
        "Phrases and keys sit in the Keychain, on this phone only.",
        "Anyone without your phrase hears only gibberish words or sound.",
        "A wipe, or the duress PIN, erases all of it: the sealed file is deleted and its key is dropped from the Keychain.",
    ]

    static let notProtectedList = [
        "That you are sending something, when, and how long it is: the words, sound or code can be seen and heard by anyone nearby.",
        "With online chat on: relays see your internet address and when you post, if you turn Tor off in Settings (it is on by default). With Tor, your internet provider can still see that you use Tor.",
        "A phrase that is lost, photographed or shared. Anyone who has it can read every message in the group, past and future: there is no forward secrecy.",
        "A phone that is unlocked, or one where someone watches you read.",
        "The app PIN only guards the screen. It adds no encryption: your messages are sealed the same way with or without it.",
        "Forensic recovery. A wipe drops the key and deletes the files, but we cannot rule out that someone with lab tools recovers traces from the phone's storage.",
        "Radio rules. Encrypted traffic may be prohibited on some radio services.",
        "Independent review: the design has not been checked by an outside cryptographer.",
    ]

    static let exportNote = "Export writes your received messages as plain text. Once shared, they are no longer encrypted and no longer erased by retention or wipe. Phrases are never included."

    /// Both ways send the same report: what was typed, the version, the iPhone model, iOS version and language.
    private static let reportHolds = "Either way it holds what you wrote, DLChat's version, and your iPhone model, iOS version and language. Never your messages, groups, phrases, keys, relays or radio details."

    static let debugLogsNote = "Send anonymously seals it so only the developer can read it and posts it through Tor: no email or internet address goes with it, so the developer cannot reply unless you write a contact in it. Send by email opens your email app, which shows your address. " + reportHolds

    static let debugLogsOfflineNote = "To send anonymously, turn on Send and receive online with Hide my internet address (Tor) above. Send by email opens your email app, which shows your address. " + reportHolds

    static let debugLogsNoEmailApp = "No email app opened. The report is copied for a short time: paste it into an email to \(SupportMail.address)."

    static func debugLogsSentAnonymously(_ relays: Int) -> String {
        "Sent anonymously: \(relays == 1 ? "1 relay" : "\(relays) relays") took it. The developer cannot see who sent it."
    }

    static let debugLogsAnonymousFailed = "No relay took it. Check your connection and try again, or send by email."

    static let debugLogsTooLong = "Too long to send anonymously. Shorten it, or send by email."

    static let deletionNote = "There are no accounts, and nothing reaches the developer unless you send a bug report. Wipe erases everything on this phone, but not sealed messages already posted to public relays."

    struct Document: Identifiable {
        let id: String
        let title: String
        let paragraphs: [String]
    }

    static let privacy = Document(id: "privacy", title: "Privacy", paragraphs: [
        "DLChat has no accounts and no analytics, and this version has no server run by the developer built in. With online chat off, nothing you type, say or receive is sent over the internet. The only other things sent are a bug report you choose to send from Settings and the Mesh Map downloads described below.",
        "When you turn on online chat, your sealed messages are posted to public Nostr relays run by other people. The default relays are relay.primal.net, relay.nostrhub.fr and nostr.data.haus, and you can change them in Settings. A relay sees when you post and how large the post is, and it can keep it. With Tor on, which is the default, a relay sees a Tor address. With Tor off it sees your internet address. Internet Messages also go through relays, sealed, and over Tor.",
        "Stored on this phone only: your groups and phrases, received messages (kept for the time you choose in Settings), and your PIN hashes. Unsent text in Send and Receive is never saved.",
        "The microphone and camera are used only while Listen or Scan is open. Audio and images are decoded in memory and not saved.",
        "The Mesh Map uses this phone's location only while it is open, to show how far away other radios are. The location stays on this phone and is never saved or sent. Worldwide radios are a download of meshmap.net's public list, through Tor when Tor is on; nothing is uploaded.",
        "The Mesh Map's street map downloads map pictures from OpenFreeMap (OpenStreetMap data) only through Tor, so OpenFreeMap sees a Tor address, not this phone's. With Tor off the street map does not load and a radar is shown instead. Map pictures are not saved on this phone.",
        "A hosted privacy policy and contact are not published yet.",
    ])

    static let terms = Document(id: "terms", title: "Terms", paragraphs: [
        "DLChat is free, open source software under the GNU General Public License, version 3. You use it at your own risk. It is provided as it is, with no warranty: no promise that it will work, be available, or keep a message private against every threat. Read what is and is not protected in Settings.",
        "You are responsible for how you use it, including any radio rules where you are. This is not legal advice, and DLChat is not approved or certified by any regulator.",
        "Keep your phrase on paper. If you lose it, or wipe the phone, nobody can recover your messages.",
        "These are plain-language terms. They have not been reviewed by a lawyer, and no legal entity or contact is named yet.",
    ])

    static let licenses = Document(id: "licenses", title: "Licenses", paragraphs: [
        "DLChat is free software: you can share and change it under the GNU General Public License, version 3 or later, with no warranty. The source code is at github.com/HarrisonFischberg/dlchat-open.",
        "DLChat uses Apple frameworks, including CryptoKit and CommonCrypto, for its cryptography, except the Schnorr signatures that online chat needs. It also includes three third-party components. swift-secp256k1, MIT License, makes those signatures. Tor.framework from iCepa, MIT License, routes online traffic through Tor, and bundles tor (BSD 3-clause License), OpenSSL (Apache 2.0 License), libevent (BSD 3-clause License) and liblzma. MapLibre Native, BSD 2-Clause License, draws the Mesh Map's street map.",
        "MapLibre Native, BSD 2-Clause License. Copyright (c) 2021 MapLibre contributors. Copyright (c) 2018-2021 MapTiler.com. Copyright (c) 2014-2020 Mapbox. Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met: Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.",
        "Street map data © OpenStreetMap contributors (Open Database License), map style and pictures by OpenFreeMap and OpenMapTiles.",
        "The 1024-word list is derived from two lists.",
        "BIP39 English word list, MIT License, from BIP-0039 (github.com/bitcoin/bips).",
        "EFF short wordlist 1, Creative Commons Attribution 3.0 US, Electronic Frontier Foundation (eff.org/dice).",
        "The frequency word list source is still awaiting a license review.",
    ])

    static let documents = [privacy, terms, licenses]
}

/// Received messages as plain text for the share sheet. Never includes phrases or keys.
enum MessageExport {
    static func text(messages: [StoredMessage], groupNames: [UUID: String], now: Date = Date()) -> String {
        guard !messages.isEmpty else { return "" }
        var lines = ["DLChat received messages, exported \(now.formatted(date: .abbreviated, time: .shortened))", ""]
        for m in messages.sorted(by: { $0.sentAt < $1.sentAt }) {
            var head = "[\(m.sentAt.formatted(date: .abbreviated, time: .shortened))]"
            if let name = groupNames[m.groupID] { head += " \(name)" }
            if !m.room.isEmpty { head += " / \(m.room)" }
            if m.duress { head += " (sent under pressure)" }
            lines.append(head)
            lines.append(m.shownText)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
