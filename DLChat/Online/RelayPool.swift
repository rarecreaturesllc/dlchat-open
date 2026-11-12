import DLCore
import Foundation
import Network

/// Talks NIP-01 to several Nostr relays at once: publish to all, subscribe on all, reconnect with
/// backoff. Knows nothing about groups or messages; events in, events out.
///
/// OnlineModel keeps one pool per group, so a relay never sees two groups' mailboxes on one socket.
/// Each pool gives Tor its own SOCKS username, and Tor (IsolateSOCKSAuth, on by default) builds a
/// separate circuit for it, so the groups also leave through different exits.
@MainActor
final class RelayPool {
    /// Called for every event a relay sends for our subscription (duplicates across relays included).
    var onEvent: ((Online.Event) -> Void)?
    /// Called when the number of connected relays changes.
    var onConnected: ((Int) -> Void)?
    /// Called when a relay has sent every stored event for our subscription (NIP-01 "EOSE").
    var onCaughtUp: (() -> Void)?
    /// NIP-42: sign-in events for a relay's challenge (one per mailbox we read).
    var authEvents: ((String, URL) -> [Online.Event])?

    private var relays: [String: RelayConnection] = [:]
    private var filter: [String: Any]?
    private var socksPort: UInt16?
    private let isolation = UUID().uuidString
    /// Made on first connect and invalidated on disconnect: an URLSession lives (with its sockets and
    /// threads) until it is invalidated, and a new pool is made every time OnlineModel reconnects.
    private var session: URLSession?

    var connectedCount: Int { relays.values.filter(\.isOpen).count }
    /// Addresses of the relays connected right now.
    var openRelays: [String] { relays.filter { $0.value.isOpen }.map(\.key).sorted() }

    /// `socksPort`: Tor's local proxy; when set, every relay socket (and its DNS lookup) goes through it.
    func connect(_ urls: [URL], via socksPort: UInt16? = nil) {
        if socksPort != self.socksPort || session == nil {
            relays.values.forEach { $0.close() }
            relays = [:]
            self.socksPort = socksPort
            session?.invalidateAndCancel()
            session = Self.session(socksPort: socksPort, isolation: isolation)
        }
        guard let session else { return }
        let wanted = Set(urls.map(\.absoluteString))
        for (url, relay) in relays where !wanted.contains(url) { relay.close(); relays[url] = nil }
        for url in urls where relays[url.absoluteString] == nil {
            let relay = RelayConnection(url: url, session: session)
            relay.onEvent = { [weak self] in self?.onEvent?($0) }
            relay.onOpenChange = { [weak self] in self.map { $0.onConnected?($0.connectedCount) } }
            relay.onCaughtUp = { [weak self] in self?.onCaughtUp?() }
            relay.authEvents = { [weak self] challenge, url in self?.authEvents?(challenge, url) ?? [] }
            relay.filter = filter
            relays[url.absoluteString] = relay
            relay.open()
        }
    }

    func disconnect() {
        relays.values.forEach { $0.close() }
        relays = [:]
        session?.invalidateAndCancel()
        session = nil
        onConnected?(0)
    }

    /// Always ephemeral: no cookies, cache or HSTS state that could link sessions over time.
    static func session(socksPort: UInt16?, isolation: String) -> URLSession {
        URLSession(configuration: configuration(socksPort: socksPort, isolation: isolation))
    }

    /// Ephemeral settings, through Tor's SOCKS proxy when a port is given. Also handed to MapLibre, so
    /// every map download goes through Tor too (the street map only opens with a port).
    static func configuration(socksPort: UInt16?, isolation: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        guard let socksPort, let port = NWEndpoint.Port(rawValue: socksPort) else { return config }
        var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
        // Not a secret: Tor only uses it to keep this pool's streams on their own circuit.
        if !isolation.isEmpty { proxy.applyCredential(username: isolation, password: isolation) }
        config.proxyConfigurations = [proxy]
        return config
    }

    /// One GET of a public file (the Mesh Map's worldwide list), through Tor's proxy when a port is given.
    /// Lives here because this file is the app's only network code (HygieneTests). Nil on any failure.
    static func download(_ url: URL, socksPort: UInt16?, isolation: String, maxBytes: Int) async -> Data? {
        let session = socksPort == nil ? URLSession(configuration: .ephemeral) : session(socksPort: socksPort, isolation: isolation)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maxBytes else { return nil }
        return data
    }

    /// Replaces the one subscription on every relay.
    func subscribe(_ filter: [String: Any]) {
        self.filter = filter
        relays.values.forEach { $0.filter = filter; $0.sendSubscription() }
    }

    /// Sends to every relay; returns how many said OK within `timeout`.
    /// `skipping`: relay addresses the person chose not to use for this message (Chat's ^ menu).
    func publish(_ event: Online.Event, timeout: Duration = .seconds(6), skipping: Set<String> = []) async -> Int {
        let sends = relays.filter { !skipping.contains($0.key) }.values.map { relay in Task { await relay.publish(event, timeout: timeout) } }
        var accepted = 0
        for send in sends where await send.value { accepted += 1 }
        return accepted
    }
}

/// One relay socket. Reconnects 2, 4, 8 ... 60 seconds after a drop until closed.
@MainActor
final class RelayConnection {
    let url: URL
    let session: URLSession
    var filter: [String: Any]?
    var onEvent: ((Online.Event) -> Void)?
    var onOpenChange: (() -> Void)?
    var onCaughtUp: (() -> Void)?
    var authEvents: ((String, URL) -> [Online.Event])?
    private var challenge: String?
    private var authed = false
    private(set) var isOpen = false { didSet { if isOpen != oldValue { onOpenChange?() } } }

    private var task: URLSessionWebSocketTask?
    private var closed = false
    private var backoff: Double = 2
    private var waiting: [String: CheckedContinuation<Bool, Never>] = [:]
    static let subscriptionID = "dlchat"

    init(url: URL, session: URLSession = .shared) { self.url = url; self.session = session }

    func open() {
        closed = false
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 256 * 1024
        self.task = task
        task.resume()
        sendSubscription()  // URLSession queues sends until the handshake finishes
        receive(on: task)
        // A pong is the first proof the socket is really up.
        task.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                if error == nil { self.isOpen = true; self.backoff = 2 } else { self.dropped() }
            }
        }
    }

    func close() {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
        waiting.values.forEach { $0.resume(returning: false) }
        waiting = [:]
    }

    func sendSubscription() {
        guard let filter, task != nil else { return }
        send(["REQ", Self.subscriptionID, filter])
    }

    func publish(_ event: Online.Event, timeout: Duration) async -> Bool {
        // Wait (up to half the time) for the socket to be really up, so the event is not lost in a handshake.
        let deadline = ContinuousClock.now + timeout / 2
        while !isOpen, task != nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        guard task != nil else { return false }
        send(["EVENT", event.json])
        let id = event.id
        return await withCheckedContinuation { continuation in
            // Same event published twice: answer the earlier caller rather than leave it hanging.
            waiting.removeValue(forKey: id)?.resume(returning: false)
            waiting[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(id, false)
            }
        }
    }

    private func finish(_ id: String, _ ok: Bool) {
        waiting.removeValue(forKey: id)?.resume(returning: ok)
    }

    private func send(_ message: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    self.isOpen = true
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: task)
                case .failure:
                    self.dropped()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String else { return }
        #if DEBUG
        if type != "EVENT", ProcessInfo.processInfo.environment["DLCHAT_RELAY_TRACE"] == "1" { print("TRACE \(url.absoluteString) \(text.prefix(200))") }
        #endif
        switch type {
        case "EVENT":
            if array.count >= 3, let json = array[2] as? [String: Any], let event = Online.Event(json: json) { onEvent?(event) }
        case "OK":
            if array.count >= 3, let id = array[1] as? String {
                let ok = array[2] as? Bool ?? false
                #if DEBUG
                if !ok { print("RELAY \(url.absoluteString) refused: \(array.count > 3 ? array[3] : "")") }
                #endif
                finish(id, ok)
            }
        case "AUTH":
            // Remember the challenge; answer it only if the relay asks us to sign in.
            if array.count >= 2, let c = array[1] as? String { challenge = c; authed = false }
        case "CLOSED":
            // "auth-required": sign in with the mailbox keys, then ask again.
            if array.count >= 3, let reason = array[2] as? String, reason.contains("auth-required"), !authed, let challenge {
                authed = true
                for event in authEvents?(challenge, url) ?? [] { send(["AUTH", event.json]) }
                sendSubscription()
            }
            #if DEBUG
            print("RELAY \(url.absoluteString) CLOSED: \(array.dropFirst())")
            #endif
        case "EOSE":
            onCaughtUp?()
        default:
            #if DEBUG
            if type == "NOTICE" { print("RELAY \(url.absoluteString) \(type): \(array.dropFirst())") }
            #endif
            break  // NOTICE and anything else: nothing to do
        }
    }

    private func dropped() {
        isOpen = false
        task = nil
        waiting.values.forEach { $0.resume(returning: false) }
        waiting = [:]
        guard !closed else { return }
        let delay = backoff
        backoff = min(backoff * 2, 60)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.closed, self.task == nil else { return }
            self.open()
        }
    }
}

/// Internet Messages route B: DLChat's private relays, reached only as Tor onion services (relay/README.md).
/// Plain HTTP inside Tor: an onion address is itself the relay's key, and Tor encrypts end to end.
/// Each instance has its own Tor isolation, so two contacts' queues never share a circuit.
@MainActor
final class OnionRelayClient {
    private let session: URLSession
    let socksPort: UInt16?

    init(socksPort: UInt16?) {
        self.socksPort = socksPort
        let config = RelayPool.configuration(socksPort: socksPort, isolation: UUID().uuidString)
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    func close() { session.invalidateAndCancel() }

    private func post(_ relay: String, _ path: String, body: Data, type: String) async -> (Data, Int)? {
        guard let base = URL(string: relay), let url = URL(string: path, relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (data, status)
    }

    private func postJSON(_ relay: String, _ path: String, _ body: [String: Any]) async -> (Data, Int)? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return await post(relay, path, body: data, type: "application/json")
    }

    /// A new queue read with `publicKey`; nil when the relay cannot be reached.
    func createQueue(relay: String, publicKey: Data) async -> (recv: String, send: String)? {
        guard let (data, status) = await post(relay, "/v1/queue", body: publicKey, type: "application/octet-stream"), status == 200,
              let ids = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let recv = ids["recv"], let send = ids["send"] else { return nil }
        return (recv, send)
    }

    /// True once the relay holds the envelope.
    func send(_ envelope: Data, to queue: OnionQueue) async -> Bool {
        await post(queue.relay, "/v1/send/" + queue.sendID, body: envelope, type: "application/octet-stream")?.1 == 204
    }

    /// Waiting envelopes (waits up to `wait` seconds for one). Nil when the relay could not be read.
    func receive(_ queue: OwnQueue, wait: Int) async -> [(id: String, data: Data)]? {
        guard let body = try? queue.signedRequest("recv", extra: ["wait": wait]),
              let (data, status) = await postJSON(queue.relay, "/v1/recv/" + queue.recvID, body), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["messages"] as? [[String: String]] else { return nil }
        return list.compactMap { item in
            guard let id = item["id"], let text = item["data"], let bytes = Data(base64Encoded: text) else { return nil }
            return (id, bytes)
        }
    }

    func acknowledge(_ ids: [String], on queue: OwnQueue) async {
        guard !ids.isEmpty, let body = try? queue.signedRequest("ack", extra: ["ids": ids]) else { return }
        _ = await postJSON(queue.relay, "/v1/ack/" + queue.recvID, body)
    }

    func delete(_ queue: OwnQueue) async {
        guard let body = try? queue.signedRequest("delete") else { return }
        _ = await postJSON(queue.relay, "/v1/delete/" + queue.recvID, body)
    }
}
