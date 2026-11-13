import CryptoKit
import XCTest
@testable import DLCore

/// Internet Messages: invite, first message, post-quantum ratchet, outer seal, both routes' wrapping.
final class DirectTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    override func setUpWithError() throws {
        // ML-KEM-768 needs iOS 26 / macOS 26.
        do { _ = try PQ.generate() } catch DirectError.needsNewerSystem { throw XCTSkip("needs macOS 26") }
    }

    /// Ana invites, Ben accepts: both contacts and the hello as Ana sees it.
    private func pair(anaRoute: DirectRoute = .privateRelays, benRoute: DirectRoute = .both) throws
        -> (ana: DirectContact, ben: DirectContact, pending: PendingInvite) {
        let queue = OwnQueue(relay: "http://abc.onion", recvID: "r1", sendID: "s1", signingKey: OwnQueue.newSigningKey().privateKey)
        let pending = try PendingInvite.make(name: "Ana", route: anaRoute, queue: queue, now: now)
        let invite = try XCTUnwrap(DirectInvite(text: pending.invite.url.absoluteString))
        let (ben, hello) = try Direct.accept(invite, myName: "Ben", myRoute: benRoute, myQueue: nil, now: now)
        let (ana, first) = try Direct.openHello(hello, pending: pending, now: now)
        XCTAssertEqual(first.kind, .hello)
        XCTAssertEqual(first.text, "Ben")
        return (ana, ben, pending)
    }

    func testInviteLinkRoundTrips() throws {
        let queue = OwnQueue(relay: "http://abc.onion", recvID: "r", sendID: "s", signingKey: Data(count: 32))
        let pending = try PendingInvite.make(name: "  Maple house  ", route: .both, queue: queue, now: now)
        let url = pending.invite.url
        XCTAssertEqual(url.scheme, "dlchat")
        XCTAssertEqual(url.host, "contact")
        let parsed = try XCTUnwrap(DirectInvite(text: url.absoluteString))
        XCTAssertEqual(parsed, pending.invite)
        XCTAssertEqual(parsed.name, "Maple house")
        XCTAssertEqual(parsed.onion, OnionQueue(relay: "http://abc.onion", sendID: "s"))
        XCTAssertEqual(parsed.route, .both)
        // Fits one QR code.
        XCTAssertLessThan(url.absoluteString.utf8.count, 2300)
        XCTAssertNil(DirectInvite(text: "dlchat://join#word-word"))
        XCTAssertNil(DirectInvite(text: "dlchat://contact#AAAA"))
    }

    func testShortLinkIsShortAndFindsTheSameInvite() throws {
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let full = pending.invite.url.absoluteString
        let short = pending.invite.link.url.absoluteString
        XCTAssertGreaterThan(full.count, 1600)
        XCTAssertLessThan(short.count, 64)
        let link = try XCTUnwrap(DirectInviteLink(text: short))
        XCTAssertEqual(link, pending.invite.link)
        // Each form parses as itself only, and the full link still works.
        XCTAssertNil(DirectInvite(text: short))
        XCTAssertNil(DirectInviteLink(text: full))
        XCTAssertEqual(DirectInviteText(text: full), .full(pending.invite))
        XCTAssertEqual(DirectInviteText(text: short), .short(link))
        XCTAssertNil(DirectInviteText(text: "dlchat://contact#AAAA"))

        // The sealed invite is in one of the mailboxes the other phone looks in, a day later too.
        let event = try Direct.linkEvent(for: pending.invite, now: now)
        let mailbox = try XCTUnwrap(event.tags.first { $0.first == "p" }?.last)
        XCTAssertTrue(Direct.linkMailboxes(link, now: now).contains(mailbox))
        XCTAssertTrue(Direct.linkMailboxes(link, now: now.addingTimeInterval(86_000)).contains(mailbox))
        let found = try XCTUnwrap(Direct.invite(from: event, link: link))
        XCTAssertEqual(found, pending.invite)

        // And the handshake from the fetched invite is the usual one.
        let (ben, hello) = try Direct.accept(found, myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        let (ana, _) = try Direct.openHello(hello, pending: pending, now: now)
        XCTAssertEqual(ana.safetyWords, ben.safetyWords)
    }

    func testShortLinkOpensOnlyItsOwnInvite() throws {
        let mine = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let other = try PendingInvite.make(name: "Eve", route: .publicRelays, queue: nil, now: now)
        let event = try Direct.linkEvent(for: other.invite, now: now)
        XCTAssertNil(Direct.invite(from: event, link: mine.invite.link))
        XCTAssertNotEqual(Direct.linkMailboxes(mine.invite.link, now: now), Direct.linkMailboxes(other.invite.link, now: now))
        // Different sizes of name pad to the same sealed size.
        let long = try PendingInvite.make(name: String(repeating: "x", count: 40), route: .publicRelays, queue: nil, now: now)
        XCTAssertEqual(try Direct.linkEvent(for: long.invite, now: now).content.count, event.content.count)
    }

    func testHandshakeGivesBothSidesTheSameSafetyWordsAndRoutes() throws {
        let (ana, ben, pending) = try pair()
        XCTAssertEqual(ana.safetyWords, ben.safetyWords)
        // Two phones on this build: eight words that cover the whole invite.
        XCTAssertEqual(ana.safetyWords.count, 8)
        XCTAssertEqual(ana.safetyBinding, pending.invite.safetyBinding)
        XCTAssertEqual(ben.safetyBinding, pending.invite.safetyBinding)
        XCTAssertEqual(ana.name, "Ben")
        XCTAssertEqual(ben.name, "Ana")
        XCTAssertEqual(ana.theirRoute, .both)
        XCTAssertEqual(ben.theirRoute, .privateRelays)
        XCTAssertEqual(ben.theirQueue, OnionQueue(relay: "http://abc.onion", sendID: "s1"))
        XCTAssertNil(ana.theirQueue)
        XCTAssertEqual(ana.inviteID, pending.id)
        // Each side's outgoing mailbox is the other's incoming one.
        XCTAssertTrue(ana.incomingMailboxes(now: now).contains(ben.outgoingMailbox(now: now)))
        XCTAssertTrue(ben.incomingMailboxes(now: now).contains(ana.outgoingMailbox(now: now)))
        XCTAssertNotEqual(ana.outgoingMailbox(now: now), ben.outgoingMailbox(now: now))
    }

    /// An invite as builds up to 28 write it: the same fields with no version byte after the name.
    private func oldInvite(_ pending: PendingInvite) throws -> DirectInvite {
        let invite = try DirectInvite(encoded: pending.invite.encoded.dropLast())
        XCTAssertEqual(invite.version, 1)
        return invite
    }

    func testInviteVersionTravelsAsOneByteOlderBuildsIgnore() throws {
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        XCTAssertEqual(pending.invite.version, 2)
        XCTAssertEqual(try DirectInvite(encoded: pending.invite.encoded).version, 2)
        // Without the byte it is the invite an older build made, and writes back out without it.
        let old = try oldInvite(pending)
        XCTAssertEqual(old.encoded, pending.invite.encoded.dropLast())
        XCTAssertEqual(old.identity, pending.invite.identity)
        XCTAssertEqual(old.name, "Ana")
        // A version from a newer build counts as the newest this build knows.
        XCTAssertEqual(try DirectInvite(encoded: pending.invite.encoded.dropLast() + Data([9])).version, 2)
    }

    func testOlderBuildOnEitherSideKeepsTheSixWords() throws {
        // Ben answers an invite from an older build: version 1 hello, six words, the old contact secret.
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let (ben, hello) = try Direct.accept(try oldInvite(pending), myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        XCTAssertEqual(try Direct.open(hello.bytes, key: pending.invite.wrapKey).first, Direct.helloTag)
        // Ana (this build, or an older one: the bytes are the same) opens it as version 1 too.
        let (ana, _) = try Direct.openHello(hello, pending: pending, now: now)
        XCTAssertNil(ana.safetyBinding)
        XCTAssertNil(ben.safetyBinding)
        // The contact secret is the one an older build works out: X25519 and the invite secret, nothing more.
        let classical = DirectContact.sharedSecrets(dh: try DirectKDF.dh(pending.identityPrivate, ben.identityPublic),
                                                    inviteSecret: pending.secret).contact
        XCTAssertEqual(ana.contactSecret, classical)
        XCTAssertEqual(ben.contactSecret, classical)
        XCTAssertEqual(ana.safetyWords, ben.safetyWords)
        XCTAssertEqual(ana.safetyWords.count, 6)
        // The first three are the words builds up to 17 showed (the top 30 bits of the same hash).
        let pair = [ana.identityPublic, ana.theirIdentity].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = Array(SHA256.hash(data: Data("DLChat/direct/v1/safety".utf8) + pair[0] + pair[1]))
        let old = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        XCTAssertEqual(Array(ana.safetyWords.prefix(3)), [22, 12, 2].map { WordList.word(at: Int((old >> UInt32($0)) & 1023)) })
        // And they still talk.
        XCTAssertTrue(ana.incomingMailboxes(now: now).contains(ben.outgoingMailbox(now: now)))
        let (_, envelope) = try Direct.seal(DirectMessage(text: "old and new"), for: ana)
        XCTAssertEqual(try Direct.open(envelope, from: ben).1.text, "old and new")
    }

    func testVersionTwoHelloAndContactSecret() throws {
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let (ben, hello) = try Direct.accept(pending.invite, myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        XCTAssertEqual(try Direct.open(hello.bytes, key: pending.invite.wrapKey).first, Direct.helloV2Tag)
        let (ana, _) = try Direct.openHello(hello, pending: pending, now: now)
        // Both sides reach the same contact secret, and it is not the X25519-only one.
        XCTAssertEqual(ana.contactSecret, ben.contactSecret)
        let dh = try DirectKDF.dh(pending.identityPrivate, ben.identityPublic)
        XCTAssertNotEqual(ana.contactSecret, DirectContact.sharedSecrets(dh: dh, inviteSecret: pending.secret).contact)
        // A stored contact from before this build has no binding and loads as a six-word contact.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ana)) as? [String: Any])
        json["safetyBinding"] = nil
        let stored = try JSONDecoder().decode(DirectContact.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(stored.safetyWords.count, 6)
        // Saved and loaded as it is, it keeps its eight.
        XCTAssertEqual(try JSONDecoder().decode(DirectContact.self, from: JSONEncoder().encode(ana)).safetyWords, ben.safetyWords)
    }

    func testSafetyWordsCoverEveryFieldOfTheInvite() throws {
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let invite = pending.invite
        let (ben, _) = try Direct.accept(invite, myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        func words(_ changed: DirectInvite) -> [String] {
            var copy = ben
            copy.safetyBinding = changed.safetyBinding
            return copy.safetyWords
        }
        XCTAssertEqual(words(invite), ben.safetyWords)
        // A swapped ML-KEM key, with both identity keys left alone, changes the words.
        let otherKEM = try PQ.generate().publicKey
        let swapped = DirectInvite(identity: invite.identity, kemPublic: otherKEM, secret: invite.secret, route: invite.route,
                                   onion: invite.onion, name: invite.name)
        XCTAssertNotEqual(words(swapped), ben.safetyWords)
        // So does a changed secret, route, queue or name.
        let changes = [
            DirectInvite(identity: invite.identity, kemPublic: invite.kemPublic, secret: Data(repeating: 7, count: 32),
                         route: invite.route, onion: invite.onion, name: invite.name),
            DirectInvite(identity: invite.identity, kemPublic: invite.kemPublic, secret: invite.secret, route: .both,
                         onion: invite.onion, name: invite.name),
            DirectInvite(identity: invite.identity, kemPublic: invite.kemPublic, secret: invite.secret, route: invite.route,
                         onion: OnionQueue(relay: "http://evil.onion", sendID: "x"), name: invite.name),
            DirectInvite(identity: invite.identity, kemPublic: invite.kemPublic, secret: invite.secret, route: invite.route,
                         onion: invite.onion, name: "Eve"),
        ]
        for changed in changes { XCTAssertNotEqual(words(changed), ben.safetyWords) }
    }

    func testNewChainWithoutThePostQuantumPartIsRefused() throws {
        var (ana, ben, _) = try pair()
        // Ana's first reply starts a new chain, so Ben must ratchet. Strip the ML-KEM ciphertext from its header.
        let (a2, envelope) = try Direct.seal(DirectMessage(text: "reply"), for: ana)
        ana = a2
        let payload = try Direct.open(envelope.bytes, key: ana.wrapKey)
        var reader = ByteReader(payload.dropFirst())
        let header = try DirectRatchet.Header.decode(&reader)
        let body = reader.rest()
        func resealed(_ change: (inout DirectRatchet.Header) -> Void) throws -> DirectEnvelope {
            var h = header
            change(&h)
            return DirectEnvelope(bytes: try Direct.seal(Data([Direct.messageTag]) + h.encoded + body, key: ana.wrapKey))
        }
        let before = ben
        XCTAssertThrowsError(try Direct.open(try resealed { $0.kemCiphertext = nil; $0.kemKeyID = nil }, from: ben)) {
            XCTAssertEqual($0 as? DirectError, .malformed)
        }
        XCTAssertThrowsError(try Direct.open(try resealed { $0.kemPublic = nil }, from: ben)) {
            XCTAssertEqual($0 as? DirectError, .malformed)
        }
        // A refused message leaves the ratchet exactly as it was, and the real message still opens.
        var ratchet = ben.ratchet
        var stripped = header
        stripped.kemCiphertext = nil
        stripped.kemKeyID = nil
        XCTAssertThrowsError(try ratchet.decrypt(stripped.encoded + body))
        XCTAssertEqual(ratchet, before.ratchet)
        let (b2, message) = try Direct.open(envelope, from: ben)
        ben = b2
        XCTAssertEqual(message.text, "reply")
    }

    func testKeyExchangeRefusesKeysThatGiveAnAllZeroSecret() throws {
        let mine = DirectKDF.newX25519()
        // Zero and one are low-order points: the shared secret would be all zeros for any private key.
        XCTAssertThrowsError(try DirectKDF.dh(mine.privateKey, Data(count: 32)))
        XCTAssertThrowsError(try DirectKDF.dh(mine.privateKey, Data([1]) + Data(count: 31)))
        // An ordinary key still works, and both sides agree.
        let theirs = DirectKDF.newX25519()
        XCTAssertEqual(try DirectKDF.dh(mine.privateKey, theirs.publicKey), try DirectKDF.dh(theirs.privateKey, mine.publicKey))
    }

    func testConversationBothWaysManyTurns() throws {
        var (ana, ben, _) = try pair()
        for turn in 0..<4 {
            for i in 0..<3 {
                let (a2, envelope) = try Direct.seal(DirectMessage(text: "ana \(turn).\(i)"), for: ana)
                ana = a2
                let (b2, opened) = try Direct.open(envelope, from: ben)
                ben = b2
                XCTAssertEqual(opened.text, "ana \(turn).\(i)")
            }
            let (b3, envelope) = try Direct.seal(DirectMessage(text: "ben \(turn)"), for: ben)
            ben = b3
            let (a3, opened) = try Direct.open(envelope, from: ana)
            ana = a3
            XCTAssertEqual(opened.text, "ben \(turn)")
        }
    }

    func testOutOfOrderAndLostMessages() throws {
        var (ana, ben, _) = try pair()
        var envelopes: [DirectEnvelope] = []
        for i in 0..<5 {
            let (a2, e) = try Direct.seal(DirectMessage(text: "m\(i)"), for: ana)
            ana = a2
            envelopes.append(e)
        }
        // 4, 1, 0 arrive; 2 and 3 never do.
        for i in [4, 1, 0] {
            let (b2, opened) = try Direct.open(envelopes[i], from: ben)
            ben = b2
            XCTAssertEqual(opened.text, "m\(i)")
        }
        // Ben replies, then Ana's late message 3 still opens.
        let (b3, reply) = try Direct.seal(DirectMessage(text: "got some"), for: ben)
        ben = b3
        let (a3, openedReply) = try Direct.open(reply, from: ana)
        ana = a3
        XCTAssertEqual(openedReply.text, "got some")
        let (_, late) = try Direct.open(envelopes[3], from: ben)
        XCTAssertEqual(late.text, "m3")
    }

    func testReplayTamperAndStrangersAreRefusedWithoutHarm() throws {
        var (ana, ben, _) = try pair()
        let (a2, envelope) = try Direct.seal(DirectMessage(text: "once"), for: ana)
        ana = a2
        let (b2, _) = try Direct.open(envelope, from: ben)
        ben = b2
        // The same envelope again does not open (its key is used up) and leaves Ben's state alone.
        XCTAssertThrowsError(try Direct.open(envelope, from: ben))
        var bytes = envelope.bytes
        bytes[bytes.count - 1] ^= 1
        XCTAssertThrowsError(try Direct.open(DirectEnvelope(bytes: bytes), from: ben))
        // Someone else's contact cannot open it.
        let (stranger, _, _) = try pair()
        XCTAssertThrowsError(try Direct.open(envelope, from: stranger)) { XCTAssertEqual($0 as? DirectError, .notForUs) }
        // Ben still reads the next real message.
        let (_, next) = try Direct.seal(DirectMessage(text: "twice"), for: ana)
        XCTAssertEqual(try Direct.open(next, from: ben).1.text, "twice")
    }

    func testEveryMessageCarriesThePostQuantumStep() throws {
        let (ana, ben, _) = try pair()
        // Ben (initiator) sent first with a KEM ciphertext to Ana's invite key; Ana's reply chain has one to Ben's.
        XCTAssertNotNil(ben.ratchet.chainCiphertext)
        XCTAssertNotNil(ana.ratchet.chainCiphertext)
        XCTAssertNotEqual(ana.ratchet.rootKey, Data())
        let (_, envelope) = try Direct.seal(DirectMessage(text: "pq"), for: ana)
        let payload = try Direct.open(envelope.bytes, key: ana.wrapKey)
        var r = ByteReader(payload.dropFirst())
        let header = try DirectRatchet.Header.decode(&r)
        XCTAssertEqual(header.kemCiphertext?.count, PQ.ciphertextSize)
        XCTAssertEqual(header.kemPublic?.count, PQ.publicKeySize)
    }

    func testOuterSealHidesLengthInBuckets() throws {
        var (ana, _, _) = try pair()
        var sizes: Set<Int> = []
        for text in ["", "hi", String(repeating: "x", count: 1000)] {
            let (a2, e) = try Direct.seal(DirectMessage(text: text), for: ana)
            ana = a2
            sizes.insert(e.bytes.count)
        }
        XCTAssertEqual(sizes, [4096])
        XCTAssertThrowsError(try Direct.seal(DirectMessage(text: String(repeating: "y", count: 5000)), for: ana)) {
            XCTAssertEqual($0 as? DirectError, .tooLarge)
        }
    }

    func testInviteWorksOnceAndExpires() throws {
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let (_, hello) = try Direct.accept(pending.invite, myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        XCTAssertThrowsError(try Direct.openHello(hello, pending: pending, now: now.addingTimeInterval(25 * 3600))) {
            XCTAssertEqual($0 as? DirectError, .expiredInvite)
        }
        // Someone else's invite cannot open it.
        let other = try PendingInvite.make(name: "Cy", route: .publicRelays, queue: nil, now: now)
        XCTAssertThrowsError(try Direct.openHello(hello, pending: other, now: now))
    }

    func testPublicRelayEventsCarryTheEnvelope() throws {
        let (ana0, ben, pending) = try pair()
        let (ana, envelope) = try Direct.seal(DirectMessage(text: "via nostr"), for: ana0)
        let event = try Direct.event(envelope, to: ana, now: now)
        XCTAssertTrue(event.isValid)
        XCTAssertEqual(event.kind, 1059)
        let (unwrapped, mailbox) = try XCTUnwrap(Direct.envelope(from: event))
        XCTAssertEqual(unwrapped, envelope)
        XCTAssertTrue(ben.incomingMailboxes(now: now).contains(mailbox))
        XCTAssertEqual(try Direct.open(unwrapped, from: ben).1.text, "via nostr")
        // First messages go to the invite's own mailbox.
        let (_, hello) = try Direct.accept(pending.invite, myName: "Dee", myRoute: .publicRelays, myQueue: nil, now: now)
        let helloEvent = try Direct.event(hello, toInvite: pending.invite, now: now)
        let (_, helloMailbox) = try XCTUnwrap(Direct.envelope(from: helloEvent))
        XCTAssertTrue(Direct.inviteMailboxes(pending, now: now).contains(helloMailbox))
    }

    func testRatchetSurvivesSavingAndLoading() throws {
        var (ana, ben, _) = try pair()
        let (a2, e1) = try Direct.seal(DirectMessage(text: "before save"), for: ana)
        ana = a2
        ben = try JSONDecoder().decode(DirectContact.self, from: try JSONEncoder().encode(ben))
        XCTAssertEqual(try Direct.open(e1, from: ben).1.text, "before save")
    }

    func testMessageIDAndTimeRoundTrip() throws {
        let message = DirectMessage(text: "héllo 👋", sentAt: now)
        let decoded = try DirectMessage(encoded: message.encoded)
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.id.count, 16)
    }

    func testRelayRequestSignatureMatchesTheRelay() throws {
        let key = Curve25519.Signing.PrivateKey()
        let queue = OwnQueue(relay: "http://abc.onion", recvID: "abcd", sendID: "ef01", signingKey: key.rawRepresentation)
        let body = try queue.signedRequest("recv", now: now, extra: ["wait": 20])
        XCTAssertEqual(body["ts"] as? Int, 1_794_000_000)
        XCTAssertEqual(body["wait"] as? Int, 20)
        let sigHex = try XCTUnwrap(body["sig"] as? String)
        let sig = Data(stride(from: 0, to: sigHex.count, by: 2).map {
            UInt8(sigHex[sigHex.index(sigHex.startIndex, offsetBy: $0)..<sigHex.index(sigHex.startIndex, offsetBy: $0 + 2)], radix: 16)!
        })
        XCTAssertTrue(key.publicKey.isValidSignature(sig, for: Data("dlchat-relay/v1/recv|abcd|1794000000".utf8)))
    }
}
