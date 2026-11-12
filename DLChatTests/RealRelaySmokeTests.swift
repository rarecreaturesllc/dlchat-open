import DLCore
import TorKit
import XCTest
@testable import DLChat

/// Posts to the real default relays. Skipped unless DLCHAT_REAL_RELAYS=1 (owner approval each time:
/// it sends sealed synthetic messages to third-party servers). Run with
/// TEST_RUNNER_DLCHAT_REAL_RELAYS=1 xcodebuild test ... -only-testing:DLChatTests/RealRelaySmokeTests
@MainActor
final class RealRelaySmokeTests: XCTestCase {
    func testDefaultRelaysAcceptAndDeliver() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DLCHAT_REAL_RELAYS"] == "1", "real relays need the owner's OK")
        try await roundTrip(via: nil)
    }

    /// The same round trip with every relay socket through real Tor. Needs both DLCHAT_REAL_RELAYS=1
    /// and DLCHAT_REAL_TOR=1.
    func testDefaultRelaysOverTor() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["DLCHAT_REAL_RELAYS"] == "1" && env["DLCHAT_REAL_TOR"] == "1", "real relays over Tor need the owner's OK")
        let port = try await Tor.shared.start(dataDirectory: OnlineModel.torDirectory) { print("TOR \($0)%") }
        try await roundTrip(via: port)
        await Tor.shared.pause()
    }

    private func roundTrip(via socksPort: UInt16?) async throws {
        let keys = Keys(phrase: try Phrase.generate(words: 10))  // throwaway group nobody else has
        for relay in (ProcessInfo.processInfo.environment["DLCHAT_RELAYS"]?.split(separator: ",").map(String.init) ?? OnlineModel.defaultRelays) {
            let url = try XCTUnwrap(URL(string: relay))
            let sender = RelayPool(), receiver = RelayPool()
            var got: [Online.Event] = []
            receiver.onEvent = { got.append($0) }
            receiver.authEvents = { challenge, url in (try? Online.authEvents(challenge: challenge, relay: url, keys: [keys])) ?? [] }
            receiver.connect([url], via: socksPort)
            receiver.subscribe(Online.filter(mailboxes: Online.mailboxes(for: keys, now: Date()), since: Date().addingTimeInterval(-3 * 86_400)))
            sender.connect([url], via: socksPort)
            let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: "dlchat relay test", keys: keys), ttl: 0)
            let event = try Online.event(wire: wire, keys: keys)
            let accepted = await sender.publish(event, timeout: .seconds(socksPort == nil ? 10 : 30))
            for _ in 0..<(socksPort == nil ? 100 : 300) where !got.contains(where: { $0.id == event.id }) { try await Task.sleep(for: .milliseconds(100)) }
            let back = got.first { $0.id == event.id }
            let text = back.flatMap { Online.wire(from: $0, trying: [keys]) }.flatMap { Receiver.readNearby(wire: $0.wire, trying: [keys])?.text }
            print("SMOKE \(relay) tor=\(socksPort != nil): accepted=\(accepted) deliveredBack=\(back != nil) opened=\(text ?? "nil")")
            XCTAssertEqual(accepted, 1, "\(relay) did not accept")
            XCTAssertEqual(text, "dlchat relay test", "\(relay) did not deliver it back")
            sender.disconnect(); receiver.disconnect()
        }
    }

    /// Add a contact, end to end on each real default relay: the short link's sealed invite is posted and
    /// fetched back, then the first message is posted and opened by the inviter. These events are about
    /// 5.5 KB, more than twice a group message, so a relay that carries group chat may still refuse them.
    func testContactInviteOverDefaultRelays() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DLCHAT_REAL_RELAYS"] == "1", "real relays need the owner's OK")
        try await contactInvite(via: nil)
    }

    func testContactInviteOverTor() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["DLCHAT_REAL_RELAYS"] == "1" && env["DLCHAT_REAL_TOR"] == "1", "real relays over Tor need the owner's OK")
        let port = try await Tor.shared.start(dataDirectory: OnlineModel.torDirectory) { print("TOR \($0)%") }
        try await contactInvite(via: port)
        await Tor.shared.pause()
    }

    private func contactInvite(via socksPort: UInt16?) async throws {
        let wait = socksPort == nil ? 100 : 300
        let since = Date().addingTimeInterval(-3 * 86_400)
        for relay in (ProcessInfo.processInfo.environment["DLCHAT_RELAYS"]?.split(separator: ",").map(String.init) ?? OnlineModel.defaultRelays) {
            let url = try XCTUnwrap(URL(string: relay))
            let pending = try PendingInvite.make(name: "Synthetic inviter", route: .publicRelays, queue: nil)
            let link = pending.invite.link

            // Inviter: posts the sealed invite and listens for the first message.
            let inviter = RelayPool(), friend = RelayPool()
            var hello: (DirectContact, DirectMessage)?
            inviter.onEvent = { event in
                guard hello == nil, case let (envelope, _)? = Direct.envelope(from: event) else { return }
                hello = try? Direct.openHello(envelope, pending: pending)
            }
            inviter.connect([url], via: socksPort)
            inviter.subscribe(Online.filter(mailboxes: Direct.inviteMailboxes(pending), since: since))
            let linkAccepted = await inviter.publish(try Direct.linkEvent(for: pending.invite), timeout: .seconds(socksPort == nil ? 10 : 30))

            // Friend: fetches the invite behind the short link, then posts the first message.
            var fetched: DirectInvite?
            friend.onEvent = { event in if fetched == nil { fetched = Direct.invite(from: event, link: link) } }
            friend.connect([url], via: socksPort)
            friend.subscribe(Online.filter(mailboxes: Direct.linkMailboxes(link), since: since))
            for _ in 0..<wait where fetched == nil { try await Task.sleep(for: .milliseconds(100)) }
            var helloAccepted = 0
            if let fetched {
                let (_, envelope) = try Direct.accept(fetched, myName: "Synthetic friend", myRoute: .publicRelays, myQueue: nil)
                helloAccepted = await friend.publish(try Direct.event(envelope, mailbox: Direct.inviteMailbox(fetched)),
                                                     timeout: .seconds(socksPort == nil ? 10 : 30))
                for _ in 0..<wait where hello == nil { try await Task.sleep(for: .milliseconds(100)) }
            }
            print("SMOKE contact \(relay) tor=\(socksPort != nil): linkAccepted=\(linkAccepted) fetched=\(fetched != nil) helloAccepted=\(helloAccepted) opened=\(hello?.1.text ?? "nil")")
            XCTAssertEqual(linkAccepted, 1, "\(relay) did not accept the sealed invite")
            XCTAssertEqual(fetched, pending.invite, "\(relay) did not give the invite back")
            XCTAssertEqual(helloAccepted, 1, "\(relay) did not accept the first message")
            XCTAssertEqual(hello?.1.text, "Synthetic friend", "\(relay) did not deliver the first message")
            inviter.disconnect(); friend.disconnect()
        }
    }

    /// The app's own proxy setup, through real Tor, to the Tor Project's checker. Tor runs with
    /// SafeSocks, so this also fails if the name was looked up outside Tor. Run with
    /// TEST_RUNNER_DLCHAT_REAL_TOR=1 xcodebuild test ... -only-testing:DLChatTests/RealRelaySmokeTests
    func testRelaySocketsGoThroughTor() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DLCHAT_REAL_TOR"] == "1", "set DLCHAT_REAL_TOR=1")
        let port = try await Tor.shared.start(dataDirectory: OnlineModel.torDirectory) { print("TOR \($0)%") }
        let (data, _) = try await RelayPool.session(socksPort: port, isolation: "smoke-test").data(from: URL(string: "https://check.torproject.org/api/ip")!)
        let text = String(decoding: data, as: UTF8.self)
        print("TOR check:", text)
        XCTAssertTrue(text.contains("\"IsTor\":true"))
        await Tor.shared.pause()
    }
}
