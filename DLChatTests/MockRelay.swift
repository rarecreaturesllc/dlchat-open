import Foundation
import Network

/// A tiny Nostr relay on localhost for tests: stores EVENTs, answers OK, and sends stored and new
/// events that match a REQ's kinds and #p. Never touches the real network.
final class MockRelay: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mock-relay")
    private var events: [[String: Any]] = []
    private var subscribers: [(NWConnection, String, [String: Any])] = []
    private(set) var port: UInt16 = 0
    var rejectAll = false
    var url: URL { URL(string: "ws://127.0.0.1:\(port)")! }
    var storedCount: Int { queue.sync { events.count } }
    private var accepted = 0
    /// How many sockets have ever connected.
    var connectionCount: Int { queue.sync { accepted } }
    /// The mailboxes each open socket asked for, one set per socket.
    var mailboxesPerSocket: [Set<String>] {
        queue.sync {
            var bySocket: [ObjectIdentifier: Set<String>] = [:]
            for (connection, _, filter) in subscribers {
                bySocket[ObjectIdentifier(connection), default: []].formUnion(filter["#p"] as? [String] ?? [])
            }
            return Array(bySocket.values)
        }
    }

    init() throws {
        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    struct NotListening: Error {}

    /// Throws instead of waiting forever when the listener fails rather than becoming ready.
    func start() async throws {
        let ready = AsyncStream<UInt16> { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener.port?.rawValue { continuation.yield(port) }
                    continuation.finish()
                case .failed, .cancelled: continuation.finish()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        for await p in ready { port = p; return }
        throw NotListening()
    }

    func stop() {
        listener.cancel()
        queue.sync { subscribers.forEach { $0.0.cancel() }; subscribers = [] }
    }

    private func accept(_ connection: NWConnection) {
        accepted += 1
        connection.start(queue: queue)
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            if let data, let array = try? JSONSerialization.jsonObject(with: data) as? [Any] { self.handle(array, from: connection) }
            self.receive(connection)
        }
    }

    private func handle(_ message: [Any], from connection: NWConnection) {
        switch message.first as? String {
        case "EVENT":
            guard let event = message.last as? [String: Any], let id = event["id"] as? String else { return }
            if rejectAll { send(["OK", id, false, "blocked"], to: connection); return }
            if !events.contains(where: { $0["id"] as? String == id }) {
                events.append(event)
                for (sub, subID, filter) in subscribers where matches(event, filter) { send(["EVENT", subID, event], to: sub) }
            }
            send(["OK", id, true, ""], to: connection)
        case "REQ":
            guard message.count >= 3, let subID = message[1] as? String, let filter = message[2] as? [String: Any] else { return }
            subscribers.removeAll { $0.0 === connection && $0.1 == subID }
            subscribers.append((connection, subID, filter))
            for event in events where matches(event, filter) { send(["EVENT", subID, event], to: connection) }
            send(["EOSE", subID], to: connection)
        default: break
        }
    }

    private func matches(_ event: [String: Any], _ filter: [String: Any]) -> Bool {
        if let kinds = filter["kinds"] as? [Int], let kind = event["kind"] as? Int, !kinds.contains(kind) { return false }
        if let wanted = filter["#p"] as? [String] {
            let tags = (event["tags"] as? [[String]]) ?? []
            if !tags.contains(where: { $0.count > 1 && $0[0] == "p" && wanted.contains($0[1]) }) { return false }
        }
        return true
    }

    private func send(_ message: [Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [meta])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}
