import DLCore
import XCTest
@testable import DLChat

/// Two phones in one group, talking through a local mock relay.
@MainActor
final class OnlineModelTests: XCTestCase {
    private var cleanup: [() -> Void] = []
    override func tearDown() { cleanup.forEach { $0() }; cleanup = [] }

    private struct Phone { let groups: GroupModel; let compose: ComposeModel; let online: OnlineModel }

    private func phone(_ phrase: Phrase, relay: URL, torStart: OnlineModel.TorStart? = nil) throws -> Phone {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-online-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Porch", prepared: PreparedGroup(phrase: phrase))
        let groups = GroupModel(vault: vault)
        let suite = "dlchat.online.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        cleanup.append { defaults.removePersistentDomain(forName: suite) }
        if torStart == nil { defaults.set(false, forKey: OnlineModel.torKey) }  // mock relay on localhost, no Tor
        let online = OnlineModel(groups: groups, defaults: defaults, torStart: torStart)
        // First in tearDown: close this phone's sockets so they don't outlive the test and keep reconnecting.
        cleanup.insert({ online.setEnabled(false) }, at: 0)
        online.setRelays([relay.absoluteString])
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        return Phone(groups: groups, compose: compose, online: online)
    }

    private func send(_ text: String, from p: Phone, readOnce: Bool = false) async -> Int {
        p.compose.text = text
        p.compose.readOnce = readOnce
        let wire = p.compose.prepareNearby()!
        let keySet = p.groups.keySets().first { $0.room == "" }!
        return await p.online.send(wire: wire, keySet: keySet)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<60 where !condition() { try await Task.sleep(for: .milliseconds(100)) }
    }

    func testAskOnceThenSendAndReceive() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, relay: relay.url), b = try phone(phrase, relay: relay.url)
        XCTAssertNil(a.online.enabled, "asked once, not assumed")
        for p in [a, b] { p.online.setEnabled(true); p.online.setActive(true) }
        try await waitFor { a.online.connected == 1 && b.online.connected == 1 }

        let accepted = await send("hello from the porch", from: a)
        XCTAssertEqual(accepted, 1)
        let groupID = b.groups.groups[0].id
        try await waitFor { !b.groups.chatMessages(groupID: groupID).isEmpty }
        let received = try XCTUnwrap(b.groups.chatMessages(groupID: groupID).first)
        XCTAssertEqual(received.text, "hello from the porch")
        XCTAssertFalse(received.isOutgoing)
        XCTAssertEqual(b.groups.messages().count, 1, "received messages also show in History")

        let mine = try XCTUnwrap(a.groups.chatMessages(groupID: a.groups.groups[0].id).first)
        XCTAssertTrue(mine.isOutgoing)
        XCTAssertEqual(mine.via, "online-direct", "relays took it, and these test phones have Tor off")
        XCTAssertEqual(mine.relays, 1)
        XCTAssertTrue(a.groups.messages().isEmpty, "sent messages stay out of History")
    }

    func testQueuedWhileUnreachableThenSent() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, relay: URL(string: "ws://127.0.0.1:1")!)
        a.online.setEnabled(true); a.online.setActive(true)
        let accepted = await send("wait for me", from: a)
        XCTAssertEqual(accepted, 0)
        let groupID = a.groups.groups[0].id
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).first?.via, "queued")
        // A relay becomes reachable: the queue goes out.
        a.online.setRelays([relay.url.absoluteString])
        try await waitFor { a.groups.chatMessages(groupID: groupID).first?.via == "online" }
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).count, 1)
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).first?.text, "wait for me")
        XCTAssertEqual(relay.storedCount, 1)
    }

    /// Swipe to reply: the reply names the original by a reference both phones compute alike, it is kept
    /// on both sides, and it survives being queued and sealed again.
    func testReplyPointsAtTheSameOriginalOnBothPhones() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, relay: URL(string: "ws://127.0.0.1:1")!), b = try phone(phrase, relay: relay.url)
        a.online.setEnabled(true); a.online.setActive(true)
        let keySetA = a.groups.keySets().first { $0.room == "" }!, keySetB = b.groups.keySets().first { $0.room == "" }!
        let groupA = a.groups.groups[0].id, groupB = b.groups.groups[0].id

        // B asks; A receives it.
        let question = try Composer.composeNearby(text: "where are you?", keys: keySetB.keys)
        XCTAssertTrue(a.online.store(wire: NearbyWire.wire(frame: question, ttl: 0)))
        XCTAssertTrue(b.online.store(wire: NearbyWire.wire(frame: question, ttl: 0)))
        let heard = try XCTUnwrap(a.groups.chatMessages(groupID: groupA).first)

        // A swipes on it and answers; no relay is reachable, so the reply waits.
        let replyFrame = try Composer.composeNearby(text: "at the gate", keys: keySetA.keys, replyTo: heard.reference)
        _ = await a.online.send(wire: NearbyWire.wire(frame: replyFrame, ttl: 0), keySet: keySetA)
        let queued = try XCTUnwrap(a.groups.chatMessages(groupID: groupA).first { $0.isOutgoing })
        XCTAssertEqual(queued.via, "queued")
        XCTAssertEqual(queued.replyTo, heard.reference.fingerprint)

        // A relay is reachable: the reply is sealed again and still points at the question.
        a.online.setRelays([relay.url.absoluteString])
        try await waitFor { a.groups.chatMessages(groupID: groupA).first { $0.isOutgoing }?.via?.hasPrefix("online") == true }
        let sent = try XCTUnwrap(a.groups.chatMessages(groupID: groupA).first { $0.isOutgoing })
        XCTAssertEqual(sent.replyTo, heard.reference.fingerprint)

        // B receives the reply: its own copy of the question is the one it points at.
        XCTAssertTrue(b.online.store(wire: NearbyWire.wire(frame: replyFrame, ttl: 0)))
        let onB = b.groups.chatMessages(groupID: groupB)
        let reply = try XCTUnwrap(onB.first { $0.text == "at the gate" })
        let original = try XCTUnwrap(onB.first { $0.reference.fingerprint == reply.replyTo })
        XCTAssertEqual(original.text, heard.text)
        XCTAssertNil(original.replyTo)
    }

    func testReadOnceIsNeverStoredAndWipeForgets() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, relay: relay.url), b = try phone(phrase, relay: relay.url)
        for p in [a, b] { p.online.setEnabled(true); p.online.setActive(true) }
        try await waitFor { a.online.connected == 1 && b.online.connected == 1 }
        _ = await send("burn after reading", from: a, readOnce: true)
        try await waitFor { !b.online.transient.isEmpty }
        XCTAssertEqual(b.online.transient.first?.text, "burn after reading")
        XCTAssertTrue(b.groups.chatMessages(groupID: b.groups.groups[0].id).isEmpty)
        XCTAssertTrue(a.groups.chatMessages(groupID: a.groups.groups[0].id).isEmpty)
        b.online.wipe()
        XCTAssertNil(b.online.enabled)
        XCTAssertTrue(b.online.transient.isEmpty)
        XCTAssertEqual(b.online.connected, 0)
    }

    private func wire(_ text: String, from p: Phone, readOnce: Bool = false) -> Data {
        p.compose.text = text
        p.compose.readOnce = readOnce
        return p.compose.prepareNearby()!
    }

    /// CODE_AUDIT §5.4: relays keep sealed copies for days; a deleted message must not come back.
    func testDeletedMessageIsNotStoredAgainFromARelay() throws {
        let phrase = try Phrase.generate(words: 10)
        let dead = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: dead), b = try phone(phrase, relay: dead)
        let sealed = wire("delete me", from: a)
        let groupID = b.groups.groups[0].id
        XCTAssertTrue(b.online.store(wire: sealed))
        let stored = try XCTUnwrap(b.groups.chatMessages(groupID: groupID).first)
        b.groups.deleteMessage(stored)
        XCTAssertTrue(b.online.store(wire: sealed), "it still opens")
        XCTAssertTrue(b.groups.chatMessages(groupID: groupID).isEmpty, "but is not stored again")
        // After a relaunch (a new OnlineModel, empty seen set) it stays gone.
        let relaunched = OnlineModel(groups: b.groups, defaults: UserDefaults(suiteName: "dlchat.online.tests.\(UUID().uuidString)")!)
        _ = relaunched.store(wire: sealed)
        XCTAssertTrue(b.groups.chatMessages(groupID: groupID).isEmpty)
    }

    /// Chat > long press > Delete: a kept message leaves the chat at once (the version bump reloads Chat),
    /// and a read-once one held only in memory is dropped. The sender is untouched.
    func testChatDeleteRemovesOnlyThisPhonesCopy() throws {
        let phrase = try Phrase.generate(words: 10)
        let dead = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: dead), b = try phone(phrase, relay: dead)
        let groupID = b.groups.groups[0].id
        XCTAssertTrue(b.online.store(wire: wire("kept one", from: a)))
        let stored = try XCTUnwrap(b.groups.chatMessages(groupID: groupID).first)
        let version = b.groups.chatVersion
        b.groups.deleteMessage(stored)
        XCTAssertGreaterThan(b.groups.chatVersion, version, "Chat reloads")
        XCTAssertTrue(b.groups.chatMessages(groupID: groupID).isEmpty)

        XCTAssertTrue(b.online.store(wire: wire("read me once", from: a, readOnce: true)))
        let once = try XCTUnwrap(b.online.transient.first)
        b.online.dismiss(id: once.id)
        XCTAssertTrue(b.online.transient.isEmpty)
    }

    func testReadOnceIsNotShownAgainAfterARelaunch() throws {
        let phrase = try Phrase.generate(words: 10)
        let dead = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: dead), b = try phone(phrase, relay: dead)
        let sealed = wire("read me once", from: a, readOnce: true)
        XCTAssertTrue(b.online.store(wire: sealed))
        XCTAssertEqual(b.online.transient.count, 1)
        let relaunched = OnlineModel(groups: b.groups, defaults: UserDefaults(suiteName: "dlchat.online.tests.\(UUID().uuidString)")!)
        _ = relaunched.store(wire: sealed)
        XCTAssertTrue(relaunched.transient.isEmpty)
    }

    /// Settings > Call sign: sealed into the sender's chat messages, shown with what the friend
    /// receives (kept or read once), kept across a relaunch, and gone after a wipe.
    func testCallSignTravelsSealedAndAWipeRemovesIt() throws {
        let phrase = try Phrase.generate(words: 10)
        let dead = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: dead), b = try phone(phrase, relay: dead)
        XCTAssertNil(a.groups.callSign)
        let sign = try XCTUnwrap(CallSign("hf", color: 2))
        a.groups.setCallSign(sign)
        XCTAssertEqual(a.groups.callSign?.letters, "HF")

        XCTAssertTrue(b.online.store(wire: wire("on my way", from: a)))
        let stored = try XCTUnwrap(b.groups.chatMessages(groupID: b.groups.groups[0].id).first)
        XCTAssertEqual(stored.text, "on my way")
        XCTAssertEqual(stored.callSign, sign)
        XCTAssertTrue(b.online.store(wire: wire("read me once", from: a, readOnce: true)))
        XCTAssertEqual(b.online.transient.first?.callSign, sign)

        // Without one, nothing is shown.
        XCTAssertTrue(a.online.store(wire: wire("no sign here", from: b)))
        XCTAssertNil(a.groups.chatMessages(groupID: a.groups.groups[0].id).first { $0.text == "no sign here" }?.callSign)

        a.groups.reload()
        XCTAssertEqual(a.groups.callSign, sign, "kept in the sealed store")
        XCTAssertTrue(a.groups.wipeEverything())
        XCTAssertNil(a.groups.callSign)
    }

    /// CODE_AUDIT §5.5: with retention "Don't keep", a message nothing took is still queued, and a
    /// sent one shows for the session without being stored.
    func testRetentionOffQueuesUnsentAndShowsSentForTheSession() async throws {
        let phrase = try Phrase.generate(words: 10)
        let a = try phone(phrase, relay: URL(string: "ws://127.0.0.1:1")!)
        a.groups.setRetention(.off)
        let groupID = a.groups.groups[0].id
        a.online.setEnabled(true); a.online.setActive(true)
        let accepted = await send("still goes out", from: a)
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).map(\.via), ["queued"])
        // Coming back to the app purges what "Don't keep" does not keep. The waiting message must survive that.
        a.groups.purgeExpired()
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).map(\.via), ["queued"])

        a.online.setEnabled(false)
        let keySet = a.groups.keySets().first { $0.room == "" }!
        await a.online.send(wire: wire("by radio", from: a), keySet: keySet, sentBy: "radio")
        XCTAssertEqual(a.online.unkept.map(\.text), ["by radio"])
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).count, 1, "the radio message is not stored")
    }

    /// The radio can stay connected while the iPhone is locked, when keys and store cannot be read.
    func testRadioMessageHeardWhileLockedIsHeldAndStoredOnUnlock() throws {
        let phrase = try Phrase.generate(words: 10)
        let nowhere = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: nowhere), b = try phone(phrase, relay: nowhere)
        let groupID = a.groups.groups[0].id
        let sealed = wire("heard in a pocket", from: b)
        var unlocked = false
        a.online.canReadKeys = { unlocked }
        a.online.storeFromRadio(sealed)
        a.online.storeFromRadio(sealed)  // a repeat from another hop
        XCTAssertTrue(a.groups.chatMessages(groupID: groupID).isEmpty)
        XCTAssertEqual(a.online.arrivals, 0, "nothing is announced before it is saved")

        unlocked = true
        a.online.setActive(true)
        XCTAssertEqual(a.groups.chatMessages(groupID: groupID).map(\.text), ["heard in a pocket"])
        XCTAssertEqual(a.online.arrivals, 1)
    }

    /// Relays hand every recent message over again at each launch: a repeat must not rewrite the store.
    func testARepeatedChatMessageDoesNotRewriteTheStore() throws {
        let phrase = try Phrase.generate(words: 10)
        let nowhere = URL(string: "ws://127.0.0.1:1")!
        let a = try phone(phrase, relay: nowhere), b = try phone(phrase, relay: nowhere)
        let sealed = wire("once is enough", from: b)
        XCTAssertTrue(a.online.store(wire: sealed))
        let stamp = a.groups.vault.stamp()
        XCTAssertNotNil(stamp)
        XCTAssertTrue(a.online.store(wire: sealed))
        XCTAssertEqual(a.groups.vault.stamp(), stamp)
        let kept = a.groups.chatMessages(groupID: a.groups.groups[0].id)
        XCTAssertEqual(kept.map(\.text), ["once is enough"])
        XCTAssertEqual(kept.first?.timesHeard, 1)
        XCTAssertEqual(a.online.arrivals, 1)
    }

    /// A read-once message is never stored, so it cannot wait in the queue: its bubble must say it did not go.
    func testReadOnceThatNothingTookSaysNotSent() async throws {
        let a = try phone(try Phrase.generate(words: 10), relay: URL(string: "ws://127.0.0.1:1")!)
        a.online.setEnabled(true); a.online.setActive(true)
        let accepted = await send("burn after reading", from: a, readOnce: true)
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(a.online.transient.map(\.via), ["unsent"])
    }

    func testEachGroupHasItsOwnSocketAndAsksOnlyForItsOwnMailboxes() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let first = try Phrase.generate(words: 10), second = try Phrase.generate(words: 10)
        let p = try phone(first, relay: relay.url)
        try p.groups.save(name: "Garden", prepared: PreparedGroup(phrase: second))
        p.online.setEnabled(true); p.online.setActive(true)
        try await waitFor { relay.mailboxesPerSocket.count == 2 }
        let sockets = relay.mailboxesPerSocket
        XCTAssertEqual(sockets.count, 2, "one socket per group")
        let expected = [first, second].map { Set(Online.mailboxes(for: Keys(phrase: $0), now: Date())) }
        XCTAssertEqual(Set(sockets), Set(expected), "each socket asks for one group's mailboxes, never both")
    }

    func testRelayListKeepsOnlyWebSocketURLs() throws {
        let p = try phone(try Phrase.generate(words: 10), relay: URL(string: "ws://127.0.0.1:1")!)
        p.online.setRelays(["wss://relay.example", " wss://relay.example ", "https://not-a-relay", "nonsense", "ws://10.0.0.2:7777"])
        XCTAssertEqual(p.online.relays, ["wss://relay.example", "ws://10.0.0.2:7777"])
    }

    /// A relay that refuses every DLChat post is dropped from a list saved by an older build; a list
    /// left empty falls back to the defaults.
    func testRefusingRelayIsDroppedFromASavedList() throws {
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)",
                          directory: FileManager.default.temporaryDirectory.appending(path: "dlchat-online-\(UUID().uuidString)", directoryHint: .isDirectory))
        cleanup.append { try? vault.wipe() }
        let groups = GroupModel(vault: vault)
        for (saved, expected) in [(["wss://relay.primal.net", "wss://nostr.bitcoiner.social", "wss://relay.example"], ["wss://relay.primal.net", "wss://relay.example"]),
                                  (["wss://nostr.bitcoiner.social"], OnlineModel.defaultRelays)] {
            let suite = "dlchat.online.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            cleanup.append { defaults.removePersistentDomain(forName: suite) }
            defaults.set(saved, forKey: OnlineModel.relaysKey)
            XCTAssertEqual(OnlineModel(groups: groups, defaults: defaults).relays, expected)
        }
        XCTAssertFalse(OnlineModel.defaultRelays.contains { OnlineModel.refusingRelays.contains($0) })
    }

    func testPlainWebSocketOnlyToLocalOrOnionRelays() throws {
        let p = try phone(try Phrase.generate(words: 10), relay: URL(string: "ws://127.0.0.1:1")!)
        p.online.setRelays(["ws://relay.example", "ws://8.8.8.8", "ws://192.168.1.5:7777", "ws://abc.onion", "ws://localhost:1"])
        XCTAssertEqual(p.online.relays, ["ws://192.168.1.5:7777", "ws://abc.onion", "ws://localhost:1"])
    }

    // MARK: Tor

    func testTorOnNeverConnectsDirectlyWhileTorStarts() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        let p = try phone(try Phrase.generate(words: 10), relay: relay.url) { progress in
            progress(40)
            try await Task.sleep(for: .seconds(3600))  // Tor never finishes in this test
            return 1
        }
        p.online.setEnabled(true)
        p.online.setTor(true)
        p.online.setActive(true)
        try await waitFor { p.online.torProgress == 40 }
        let accepted = await send("wait for tor", from: p)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(accepted, 0, "nothing goes out before Tor is ready")
        XCTAssertEqual(relay.connectionCount, 0, "no direct socket to the relay")
        XCTAssertEqual(p.online.connected, 0)
        XCTAssertEqual(p.groups.chatMessages(groupID: p.groups.groups[0].id).first?.via, "queued")
        XCTAssertEqual(TorStatus.text(p.online), "Connecting to Tor (40%). Messages wait until it is ready.")
    }

    func testTorFailureStaysOfflineAndTurningTorOffGoesDirect() async throws {
        let relay = try MockRelay(); try await relay.start(); defer { relay.stop() }
        struct NoTor: Error {}
        let p = try phone(try Phrase.generate(words: 10), relay: relay.url) { _ in throw NoTor() }
        p.online.setEnabled(true)
        p.online.setTor(true)
        p.online.setActive(true)
        try await waitFor { p.online.torFailed }
        XCTAssertTrue(p.online.torFailed)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(relay.connectionCount, 0, "a failed Tor does not fall back to a direct socket")

        p.online.setTor(false)  // the person chooses to go direct
        try await waitFor { p.online.connected == 1 }
        XCTAssertEqual(p.online.connected, 1)
        XCTAssertNil(TorStatus.text(p.online))
    }

    func testTorIsOnByDefaultAndWipeRestoresTheDefault() throws {
        let p = try phone(try Phrase.generate(words: 10), relay: URL(string: "ws://127.0.0.1:1")!) { _ in 1 }
        XCTAssertTrue(p.online.torOn, "on by default")
        p.online.setTor(false)
        XCTAssertFalse(p.online.torOn)
        p.online.wipe()
        XCTAssertTrue(p.online.torOn)
        XCTAssertNil(p.online.enabled, "online itself is off again after a wipe")
    }
}
