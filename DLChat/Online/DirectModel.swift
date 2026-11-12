import DLCore
import Foundation
import Observation
import UIKit

/// One Internet Message as Chat shows it.
struct DirectChatMessage: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case queued, sent, received }
    let id: String          // the message's own id (hex), the same on both phones
    let contactID: UUID
    let text: String
    let sentAt: Date
    let recordedAt: Date
    let outgoing: Bool
    var status: Status
    /// "private", "public" or "private+public": which routes carried it.
    var via: String?
}

/// A sealed envelope waiting for a route (Tor still connecting, relay unreachable). Sent again as the
/// same bytes, so the other phone drops a second copy.
struct DirectOutboxItem: Codable, Equatable, Identifiable {
    let id: String          // envelope fingerprint
    let messageID: String?  // nil for a first message (hello)
    let contactID: UUID?
    let envelope: Data
    let route: DirectRoute
    let queue: OnionQueue?
    let mailbox: String
    let created: Date
    var sentPrivate = false
    var sentPublic = false

    var done: Bool { (!route.usesPrivate || queue == nil || sentPrivate) && (!route.usesPublic || sentPublic) }
}

/// Everything Internet Messages keep, sealed in the Vault (`direct.bin`). Erased by Wipe with the Vault.
struct DirectStore: Codable, Equatable {
    var contacts: [DirectContact] = []
    var pending: [PendingInvite] = []
    var messages: [DirectChatMessage] = []
    var outbox: [DirectOutboxItem] = []
    var unread: [UUID: Int] = [:]
    /// Envelopes already opened or refused (fingerprints), so a copy from the other route is skipped.
    var seen: [String] = []
    var myName = ""
    /// Public relays by default (owner decision 2026-11-09) until DLChat has a private relay running.
    var route: DirectRoute = .publicRelays
    var privateRelays: [String] = DirectModel.defaultPrivateRelays
    /// Disappearing messages: 7 days by default (owner decision 2026-11-09).
    var keep: Retention = .week
}

/// Internet Messages: one-to-one chats with anyone who has DLChat, no phone number, no group phrase.
/// Post-quantum Double Ratchet (DLCore `Direct`), always over Tor. Each person picks how their own
/// messages reach them: DLChat's private onion relays (route B), public Nostr relays (route A), or both.
/// Design: docs/design/internet-messages.md.
@MainActor
@Observable
final class DirectModel {
    /// DLChat's own relays (route B), as `http://<address>.onion`. Empty until the owner sets up the
    /// servers (relay/deploy/setup.sh); while empty, "Private relays" falls back to public relays.
    static let defaultPrivateRelays: [String] = []

    private(set) var store = DirectStore()
    /// Counts new incoming messages, for RootView's banner.
    private(set) var arrivals = 0
    /// A problem to show (Tor off, a relay unreachable), or nil.
    private(set) var problem: String?
    /// The contact whose chat is on screen: its messages are not counted as unread.
    var openContact: UUID? { didSet { if let openContact { markRead(openContact) } } }

    @ObservationIgnored private let online: OnlineModel
    @ObservationIgnored private let vault: Vault?
    @ObservationIgnored private var active = false
    /// The last save failed: what is in memory is not on the phone's storage yet.
    @ObservationIgnored private var unsaved = false
    @ObservationIgnored private var pools: [String: RelayPool] = [:]
    @ObservationIgnored private var polls: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var clients: [String: OnionRelayClient] = [:]
    @ObservationIgnored private var sender: OnionRelayClient?
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var lastPort: UInt16?
    static let fileName = "direct.bin"
    /// DEBUG and UI tests only: talk to a local relay without Tor.
    @ObservationIgnored var allowWithoutTor = false

    init(online: OnlineModel, vault: Vault?) {
        self.online = online
        self.vault = vault
        load()
    }

    // MARK: Store

    private func load() {
        guard let vault, let data = try? vault.readStore(named: Self.fileName),
              let decoded = try? Self.decoder.decode(DirectStore.self, from: data) else { return }
        store = decoded
        purgeExpired()
    }

    /// False when the store could not be written (the iPhone is locked). `unsaved` then stays set until a
    /// later save works, so nothing is acknowledged to a relay while it exists here in memory only.
    @discardableResult
    private func save() -> Bool {
        guard let vault else { return true }  // no vault: kept in memory only, by design
        guard let data = try? Self.encoder.encode(store), (try? vault.writeStore(data, named: Self.fileName)) != nil else {
            unsaved = true
            return false
        }
        unsaved = false
        return true
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    var contacts: [DirectContact] { store.contacts }
    var hasAnything: Bool { !store.contacts.isEmpty || !store.pending.isEmpty }
    var route: DirectRoute { store.route }
    var keep: Retention { store.keep }
    var myName: String { store.myName }
    var privateRelays: [String] { store.privateRelays }
    /// Private relays chosen but none set up: messages to this phone come by public relays meanwhile.
    var privateUnavailable: Bool { store.route.usesPrivate && store.privateRelays.isEmpty }

    func contact(_ id: UUID) -> DirectContact? { store.contacts.first { $0.id == id } }

    func messages(for contactID: UUID) -> [DirectChatMessage] {
        store.messages.filter { $0.contactID == contactID }.sorted { $0.recordedAt < $1.recordedAt }
    }

    func unread(_ contactID: UUID) -> Int { store.unread[contactID] ?? 0 }
    var totalUnread: Int { store.unread.values.reduce(0, +) }

    func lastMessage(_ contactID: UUID) -> DirectChatMessage? {
        store.messages.filter { $0.contactID == contactID }.max { $0.recordedAt < $1.recordedAt }
    }

    func markRead(_ contactID: UUID) {
        guard store.unread[contactID] != nil else { return }
        store.unread[contactID] = nil
        save()
    }

    // MARK: Settings

    func setRoute(_ route: DirectRoute) {
        store.route = route
        save()
        refresh()
    }

    func setKeep(_ keep: Retention) {
        store.keep = keep
        purgeExpired()
        save()
    }

    func setMyName(_ name: String) {
        store.myName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DirectInvite.maxName))
        save()
    }

    func setPrivateRelays(_ list: [String]) {
        let clean = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { Self.isAllowedPrivateRelay($0) }
        store.privateRelays = Array(NSOrderedSet(array: clean)) as? [String] ?? clean
        save()
    }

    /// Private relays are onion services (plain http inside Tor). Local addresses only for testing.
    static func isAllowedPrivateRelay(_ text: String) -> Bool {
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return false }
        switch url.scheme?.lowercased() {
        case "http": return host.hasSuffix(".onion") || host == "127.0.0.1" || host == "localhost"
        case "https": return true
        default: return false
        }
    }

    /// Disappearing messages: drops anything older than the setting.
    func purgeExpired(now: Date = Date()) {
        store.pending.removeAll { $0.isExpired(now: now) }
        guard let seconds = store.keep.seconds, seconds > 0 else { return }
        let cutoff = now.addingTimeInterval(-seconds)
        let before = store.messages.count
        store.messages.removeAll { $0.recordedAt < cutoff }
        if store.messages.count != before { save() }
    }

    // MARK: Network state

    /// The Tor port to use, or nil while Tor is not ready (Internet Messages never go out without Tor).
    private var port: UInt16? {
        if let port = online.torPort { return port }
        return nil
    }

    private var canConnect: Bool { allowWithoutTor || port != nil }

    func setActive(_ value: Bool) {
        active = value
        refresh()
    }

    /// Opens or closes listening to match contacts, invites, routes and Tor.
    func refresh() {
        guard active, hasAnything else { closeAll(); problem = nil; return }
        if !allowWithoutTor {
            guard online.torOn else {
                closeAll()
                problem = "Internet Messages only travel over Tor. Turn Tor back on in Settings > Online chat."
                return
            }
            guard let port else {
                closeAll()
                online.requestTor()
                problem = online.torFailed ? "Tor could not connect. Messages wait here until it does." : nil
                return
            }
            if port != lastPort { closeAll(); lastPort = port }
        }
        problem = nil
        listen()
        Task { await flush() }
        if retryTask == nil {
            retryTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled else { return }
                    await self.flush()
                }
            }
        }
    }

    private func closeAll() {
        pools.values.forEach { $0.disconnect() }
        pools = [:]
        polls.values.forEach { $0.cancel() }
        polls = [:]
        clients.values.forEach { $0.close() }
        clients = [:]
        sender?.close()
        sender = nil
        retryTask?.cancel()
        retryTask = nil
    }

    /// What this phone listens on: per contact (and per open invite) its own sockets and Tor circuit,
    /// so no relay can tell that two mailboxes or queues belong to one phone.
    private func listen() {
        var wantedPools: [String: [String]] = [:]
        var wantedPolls: [String: OwnQueue] = [:]
        let since = Date().addingTimeInterval(-Online.lifetime)
        for contact in store.contacts {
            let key = contact.id.uuidString
            if effectiveRoute(contact.myRoute, queue: contact.myQueue).usesPublic || contact.myQueue == nil {
                wantedPools[key] = contact.incomingMailboxes()
            }
            if let queue = contact.myQueue { wantedPolls[key] = queue }
        }
        for pending in store.pending {
            let key = "invite-" + pending.id.uuidString
            wantedPools[key] = Direct.inviteMailboxes(pending)
            if let queue = pending.queue { wantedPolls[key] = queue }
        }
        let urls = online.relays.compactMap(URL.init(string:))
        for (key, pool) in pools where wantedPools[key] == nil { pool.disconnect(); pools[key] = nil }
        for (key, mailboxes) in wantedPools {
            let pool = pools[key] ?? {
                let made = RelayPool()
                made.onEvent = { [weak self] event in self?.receive(event: event, key: key) }
                pools[key] = made
                return made
            }()
            pool.connect(urls, via: port)
            // Back past the blur on created_at (up to 2 days), so nothing sent while away is missed.
            pool.subscribe(Online.filter(mailboxes: mailboxes, since: since))
        }
        for (key, task) in polls where wantedPolls[key] == nil { task.cancel(); polls[key] = nil; clients[key]?.close(); clients[key] = nil }
        for (key, queue) in wantedPolls where polls[key] == nil {
            let client = OnionRelayClient(socksPort: port)
            clients[key] = client
            polls[key] = Task { [weak self] in await self?.poll(queue, key: key, client: client) }
        }
    }

    /// Long-polls one queue while active; backs off when the relay cannot be reached.
    private func poll(_ queue: OwnQueue, key: String, client: OnionRelayClient) async {
        var backoff: Double = 2
        while !Task.isCancelled {
            guard let items = await client.receive(queue, wait: 20) else {
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 60)
                continue
            }
            backoff = 2
            var done: [String] = []
            let isInvite = key.hasPrefix("invite-")
            for item in items where receive(envelope: DirectEnvelope(bytes: item.data), key: key, via: "private") || !isInvite {
                done.append(item.id)
            }
            // Not written to this phone yet (it is locked): leave it all on the relay and ask again later.
            if unsaved { try? await Task.sleep(for: .seconds(15)); continue }
            // Deleted on the relay once stored here (a contact's queue also drops what never opens). On an
            // invite's queue, a message that overtook the first one stays until the contact exists.
            await client.acknowledge(done, on: queue)
            // Something waits that cannot open yet: the relay would answer at once, so do not spin.
            if done.count < items.count { try? await Task.sleep(for: .seconds(15)) }
        }
    }

    // MARK: Receive

    private func receive(event: Online.Event, key: String) {
        guard case let (envelope, _)? = Direct.envelope(from: event) else { return }
        _ = receive(envelope: envelope, key: key, via: "public")
    }

    /// An envelope for a contact (key = its id) or an open invite ("invite-<id>").
    /// True once the envelope is stored here (or was already).
    @discardableResult
    private func receive(envelope: DirectEnvelope, key: String, via: String) -> Bool {
        let fingerprint = envelope.fingerprint
        // Seen before: stored already, unless that save failed. Then try once more before saying so.
        guard !store.seen.contains(fingerprint) else { return !unsaved || save() }
        if key.hasPrefix("invite-") {
            guard let id = UUID(uuidString: String(key.dropFirst(7))),
                  let pending = store.pending.first(where: { $0.id == id }),
                  case let (contact, _)? = try? Direct.openHello(envelope, pending: pending) else { return false }
            // One use: the invite is gone, its keys live on in the contact only.
            store.pending.removeAll { $0.id == id }
            store.contacts.append(contact)
            remember(fingerprint)
            arrivals += 1
            let saved = save()
            Notifier.newMessage()
            refresh()
            return saved
        }
        guard let id = UUID(uuidString: key), let index = store.contacts.firstIndex(where: { $0.id == id }),
              case let (updated, message)? = try? Direct.open(envelope, from: store.contacts[index]) else { return false }
        store.contacts[index] = updated
        remember(fingerprint)
        let messageID = message.id.map { String(format: "%02x", $0) }.joined()
        if message.kind == .text, !store.messages.contains(where: { $0.id == messageID }) {
            store.messages.append(DirectChatMessage(id: messageID, contactID: id, text: message.text, sentAt: message.sentAt,
                                                    recordedAt: Date(), outgoing: false, status: .received, via: via))
            if openContact != id { store.unread[id, default: 0] += 1 }
            arrivals += 1
            Notifier.newMessage()
        }
        return save()
    }

    private func remember(_ fingerprint: String) {
        store.seen.append(fingerprint)
        if store.seen.count > 5000 { store.seen.removeFirst(store.seen.count - 5000) }
    }

    // MARK: Invites

    /// The route actually used: private needs a queue on a private relay; without one, public.
    private func effectiveRoute(_ route: DirectRoute, queue: OwnQueue?) -> DirectRoute {
        route.usesPrivate && queue == nil ? .publicRelays : route
    }

    /// A queue on the first private relay that answers, or nil (no relays set, or none reachable).
    private func makeQueue() async -> OwnQueue? {
        guard store.route.usesPrivate, canConnect else { return nil }
        let client = OnionRelayClient(socksPort: port)
        defer { client.close() }
        for relay in store.privateRelays {
            let key = OwnQueue.newSigningKey()
            if let ids = await client.createQueue(relay: relay, publicKey: key.publicKey) {
                return OwnQueue(relay: relay, recvID: ids.recv, sendID: ids.send, signingKey: key.privateKey)
            }
        }
        return nil
    }

    /// Waits (up to 90 s) for Tor, so an invite can carry a private relay queue.
    private func waitForTor() async {
        guard !allowWithoutTor else { return }
        // Someone tapped Make invite or Connect: an earlier failed start is tried again, not left failed
        // until they find Settings (a friend's first Tor start on a new install can fail once).
        if online.torFailed { online.retryTor() }
        online.requestTor()
        let deadline = ContinuousClock.now + .seconds(90)
        while online.torPort == nil, online.torOn, !online.torFailed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// A new one-time invite to show as a QR code or share as a link.
    func makeInvite() async throws -> PendingInvite {
        var queue: OwnQueue?
        if store.route.usesPrivate, !store.privateRelays.isEmpty {
            await waitForTor()
            queue = await makeQueue()
        }
        let route = effectiveRoute(store.route, queue: queue)
        let pending = try PendingInvite.make(name: store.myName, route: route, queue: queue)
        store.pending.append(pending)
        save()
        refresh()
        return pending
    }

    /// Posts the full invite, sealed, for its short link. True once a relay took it; then the short link
    /// works. A private-relays-only invite stays a full link, since this would put it on public relays.
    func publishLink(for pending: PendingInvite) async -> Bool {
        guard pending.route.usesPublic else { return false }
        await waitForTor()
        guard canConnect, let event = try? Direct.linkEvent(for: pending.invite) else { return false }
        let pool = RelayPool()
        pool.connect(online.relays.compactMap(URL.init(string:)), via: port)
        defer { pool.disconnect() }
        return await pool.publish(event, timeout: .seconds(20)) > 0
    }

    /// The invite behind a short link, fetched from the relays, or nil if none had it within `timeout`.
    func fetchInvite(_ link: DirectInviteLink, timeout: Duration = .seconds(45)) async -> DirectInvite? {
        await waitForTor()
        guard canConnect else { return nil }
        let pool = RelayPool()
        var found: DirectInvite?
        pool.onEvent = { event in if found == nil { found = Direct.invite(from: event, link: link) } }
        pool.connect(online.relays.compactMap(URL.init(string:)), via: port)
        defer { pool.disconnect() }
        // Back past the blur on created_at (up to 2 days) and the invite's own day.
        pool.subscribe(Online.filter(mailboxes: Direct.linkMailboxes(link), since: Date().addingTimeInterval(-3 * 86_400)))
        let deadline = ContinuousClock.now + timeout
        while found == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(300))
        }
        return found
    }

    func cancelInvite(_ id: UUID) {
        guard let pending = store.pending.first(where: { $0.id == id }) else { return }
        store.pending.removeAll { $0.id == id }
        save()
        if let queue = pending.queue, canConnect {
            let client = OnionRelayClient(socksPort: port)
            Task { await client.delete(queue); client.close() }
        }
        refresh()
    }

    /// Accepting someone's invite: the new contact, whose first message is on its way.
    func accept(_ invite: DirectInvite) async throws -> DirectContact {
        var queue: OwnQueue?
        if store.route.usesPrivate, !store.privateRelays.isEmpty {
            await waitForTor()
            queue = await makeQueue()
        }
        let route = effectiveRoute(store.route, queue: queue)
        let (contact, hello) = try Direct.accept(invite, myName: store.myName, myRoute: route, myQueue: queue)
        store.contacts.append(contact)
        let theirRoute = invite.route.usesPrivate && invite.onion == nil ? DirectRoute.publicRelays : invite.route
        store.outbox.append(DirectOutboxItem(id: hello.fingerprint, messageID: nil, contactID: contact.id, envelope: hello.bytes,
                                             route: theirRoute, queue: invite.onion,
                                             mailbox: Direct.inviteMailbox(invite), created: Date()))
        save()
        refresh()
        return contact
    }

    // MARK: Send

    /// Seals and sends a message; it shows at once, as queued until a route takes it.
    func send(_ text: String, to contactID: UUID) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = store.contacts.firstIndex(where: { $0.id == contactID }) else { return }
        let message = DirectMessage(text: trimmed)
        let contact = store.contacts[index]
        let (updated, envelope) = try Direct.seal(message, for: contact)
        store.contacts[index] = updated
        let messageID = message.id.map { String(format: "%02x", $0) }.joined()
        store.messages.append(DirectChatMessage(id: messageID, contactID: contactID, text: trimmed, sentAt: message.sentAt,
                                                recordedAt: Date(), outgoing: true, status: .queued))
        let theirRoute = contact.theirRoute.usesPrivate && contact.theirQueue == nil ? DirectRoute.publicRelays : contact.theirRoute
        store.outbox.append(DirectOutboxItem(id: envelope.fingerprint, messageID: messageID, contactID: contactID, envelope: envelope.bytes,
                                             route: theirRoute, queue: contact.theirQueue,
                                             mailbox: Direct.outgoingMailbox(contact), created: Date()))
        remember(envelope.fingerprint)
        save()
        Task { await flush() }
    }

    /// Sends whatever is waiting, by the receiver's routes. One flush at a time.
    func flush() async {
        guard active, canConnect, !flushing, !store.outbox.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        let client = sender ?? OnionRelayClient(socksPort: port)
        sender = client
        for item in store.outbox {
            var current = item
            if current.route.usesPrivate, let queue = current.queue, !current.sentPrivate {
                current.sentPrivate = await client.send(current.envelope, to: queue)
            }
            if current.route.usesPublic, !current.sentPublic,
               let event = try? Direct.event(DirectEnvelope(bytes: current.envelope), mailbox: current.mailbox) {
                let pool = RelayPool()
                pool.connect(online.relays.compactMap(URL.init(string:)), via: port)
                current.sentPublic = await pool.publish(event, timeout: .seconds(20)) > 0
                pool.disconnect()
            }
            guard let index = store.outbox.firstIndex(where: { $0.id == item.id }) else { continue }
            store.outbox[index] = current
            if let messageID = current.messageID, current.sentPrivate || current.sentPublic,
               let m = store.messages.firstIndex(where: { $0.id == messageID }) {
                store.messages[m].status = .sent
                store.messages[m].via = [current.sentPrivate ? "private" : nil, current.sentPublic ? "public" : nil]
                    .compactMap { $0 }.joined(separator: "+")
            }
            if current.done { store.outbox.remove(at: index) }
            save()
        }
    }

    // MARK: Contacts

    func rename(_ contactID: UUID, to name: String) {
        guard let index = store.contacts.firstIndex(where: { $0.id == contactID }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.contacts[index].name = String(clean.prefix(DirectInvite.maxName))
        save()
    }

    /// Removes a contact, its messages and its queue (the relay is asked to delete it, best effort).
    func remove(_ contactID: UUID) {
        guard let contact = contact(contactID) else { return }
        store.contacts.removeAll { $0.id == contactID }
        store.messages.removeAll { $0.contactID == contactID }
        store.outbox.removeAll { $0.contactID == contactID }
        store.unread[contactID] = nil
        save()
        if let queue = contact.myQueue, canConnect {
            let client = OnionRelayClient(socksPort: port)
            Task { await client.delete(queue); client.close() }
        }
        refresh()
    }

    /// Panic wipe and duress: close everything and forget it all (the Vault file goes with the Vault).
    /// Relays are not contacted: queues nobody reads expire there on their own after 60 days.
    func wipe() {
        closeAll()
        store = DirectStore()
        vault?.removeStore(named: Self.fileName)
        arrivals = 0
        problem = nil
        openContact = nil
    }
}
