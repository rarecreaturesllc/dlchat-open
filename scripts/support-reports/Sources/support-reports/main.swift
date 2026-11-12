import CryptoKit
import DLCore
import Foundation

// DLChat anonymous support reports (Settings → Send anonymously), read on the developer's Mac.
//
//   swift run --package-path scripts/support-reports              last 45 days, the app's default relays
//   swift run --package-path scripts/support-reports 10 wss://x   last 10 days, plus another relay
//
// The private key comes from the macOS Keychain item "DLChat support key" (or DLCHAT_SUPPORT_KEY).
// This connects to the relays directly, not through Tor: they see this Mac's address asking for the
// support mailbox. Reports cannot be answered; a sender who wants a reply writes a contact in them.

/// Keep in step with `OnlineModel.defaultRelays`; a person who changed their relays in Settings may
/// have sent elsewhere (pass those relays as arguments).
let defaultRelays = ["wss://relay.primal.net", "wss://relay.nostrhub.fr", "wss://nostr.data.haus"]

let arguments = Array(CommandLine.arguments.dropFirst())
let days = arguments.first.flatMap(Double.init) ?? 45
let relays = defaultRelays + arguments.filter { $0.hasPrefix("wss://") || $0.hasPrefix("ws://") }

func privateKey() -> Curve25519.KeyAgreement.PrivateKey? {
    var secret = ProcessInfo.processInfo.environment["DLCHAT_SUPPORT_KEY"]
    if secret == nil {
        let security = Process()
        security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        security.arguments = ["find-generic-password", "-s", "DLChat support key", "-w"]
        let output = Pipe()
        security.standardOutput = output
        security.standardError = FileHandle.nullDevice
        try? security.run()
        security.waitUntilExit()
        secret = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
    guard let data = secret.flatMap({ Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return nil }
    return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
}

/// Every event a relay has for the support mailbox, until it says it has sent them all (or 20 s pass).
func fetch(_ relay: String, since: Date) async -> (relay: String, events: [Online.Event]?) {
    guard let url = URL(string: relay) else { return (relay, nil) }
    let socket = URLSession.shared.webSocketTask(with: url)
    socket.resume()
    let timer = Task {
        try? await Task.sleep(for: .seconds(20))
        socket.cancel(with: .goingAway, reason: nil)
    }
    defer { timer.cancel(); socket.cancel(with: .goingAway, reason: nil) }
    let request: [Any] = ["REQ", "support", SupportReport.filter(since: since)]
    guard let body = try? JSONSerialization.data(withJSONObject: request),
          (try? await socket.send(.string(String(decoding: body, as: UTF8.self)))) != nil else { return (relay, nil) }
    var events: [Online.Event] = []
    while let message = try? await socket.receive() {
        guard case .string(let text) = message,
              let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
              let type = array.first as? String else { continue }
        if type == "EOSE" || type == "CLOSED" { return (relay, events) }
        if type == "EVENT", array.count >= 3, let json = array[2] as? [String: Any], let event = Online.Event(json: json) {
            events.append(event)
        }
    }
    return (relay, events.isEmpty ? nil : events)
}

guard let key = privateKey() else {
    print("No support key. It lives in the Keychain item \"DLChat support key\"; restore it from your backup.")
    exit(1)
}
guard key.publicKey.rawRepresentation.base64EncodedString() == SupportReport.developerKey else {
    print("This key does not match the one built into DLChat, so it cannot open these reports.")
    exit(1)
}

let since = Date().addingTimeInterval(-days * 86_400)
var seen = Set<String>()
var reports: [(date: Date, text: String)] = []
var unreadable = 0
await withTaskGroup(of: (relay: String, events: [Online.Event]?).self) { group in
    for relay in relays { group.addTask { await fetch(relay, since: since) } }
    for await (relay, events) in group {
        print("\(relay): \(events.map { "\($0.count) event(s)" } ?? "no answer")")
        for event in events ?? [] where seen.insert(event.id).inserted {
            if let text = SupportReport.text(from: event, privateKey: key) {
                reports.append((Date(timeIntervalSince1970: TimeInterval(event.createdAt)), text))
            } else {
                unreadable += 1
            }
        }
    }
}

print("\n\(reports.count) report(s) from the last \(Int(days)) days\(unreadable > 0 ? " (\(unreadable) other post(s) that do not open with this key)" : "").")
for report in reports.sorted(by: { $0.date < $1.date }) {
    // created_at is blurred up to 2 days back on purpose, so the real send time is that or up to 2 days later.
    print("\n=== sent on or up to 2 days after \(report.date.formatted(date: .abbreviated, time: .shortened)) ===")
    print(report.text)
}
