import Foundation

/// The Meshtastic chats' messages and hourly message counts, with how long to keep them.
///
/// `.off` (the default) is how Meshtastic chats always worked: nothing is written anywhere and
/// everything is gone when DLChat closes. Any other setting is opt-in: the archive is then saved
/// only inside the sealed Vault store (`GroupBook`), dropped once older than the setting, and
/// erased with everything else by Wipe and the duress PIN.
struct MeshArchive: Codable, Equatable {
    var keep: Retention = .off
    var texts: [MeshConversation: [MeshText]] = [:]
    /// One entry per hour in which DLChat was connected to the radio, oldest first. An hour with no
    /// entry was not listened to, which is different from an hour in which nothing was heard.
    var hours: [MeshHour] = []

    /// Caps, so a busy public channel cannot grow the store without end: about 2 MB at most.
    static let maxPerConversation = 1000
    static let maxTotal = 5000
    static let maxHours = 90 * 24

    var totalTexts: Int { texts.values.reduce(0) { $0 + $1.count } }

    mutating func append(_ message: MeshText, to conversation: MeshConversation) {
        texts[conversation, default: []].append(message)
        if let n = texts[conversation]?.count, n > Self.maxPerConversation {
            texts[conversation]?.removeFirst(n - Self.maxPerConversation)
        }
        var total = totalTexts
        while total > Self.maxTotal {
            // Drop the oldest message of all conversations.
            guard let oldest = texts.filter({ !$0.value.isEmpty }).min(by: { $0.value[0].at < $1.value[0].at })?.key else { break }
            texts[oldest]?.removeFirst()
            if texts[oldest]?.isEmpty == true { texts[oldest] = nil }
            total -= 1
        }
    }

    /// The radio was connected at `now`: the hour counts as listened to, even if nothing is heard.
    mutating func listened(at now: Date) {
        let start = MeshHour.start(of: now)
        if hours.last?.start == start { return }
        hours.append(MeshHour(start: start))
        if hours.count > Self.maxHours { hours.removeFirst(hours.count - Self.maxHours) }
    }

    /// One message heard on a channel (not sent by this phone).
    mutating func counted(channel: UInt32, at now: Date) {
        listened(at: now)
        hours[hours.count - 1].counts[channel, default: 0] += 1
    }

    /// Drops messages and counts older than the setting. Nothing goes by age with `.off` or `.forever`.
    mutating func purge(now: Date) {
        guard let keep = keep.seconds, keep > 0 else { return }
        let cutoff = now.addingTimeInterval(-keep)
        for (conversation, list) in texts {
            let kept = list.filter { $0.at > cutoff }
            texts[conversation] = kept.isEmpty ? nil : kept
        }
        hours.removeAll { $0.start.addingTimeInterval(3600) <= cutoff }
    }

    /// Messages that were still going out when DLChat closed cannot be confirmed any more.
    mutating func restored() {
        for (conversation, list) in texts {
            texts[conversation] = list.map { m in
                var m = m
                if m.state == .sending { m.state = .failed("DLChat closed before the radio confirmed it") }
                return m
            }
        }
    }

    /// Counts for one channel in buckets of `bucket` (an hour or a local day), the last `count` buckets
    /// up to `now`, oldest first. `nil` means DLChat was not connected at any time in that bucket.
    func series(channel: UInt32, bucket: Calendar.Component, count: Int, now: Date, calendar: Calendar = .current) -> [MeshBar] {
        guard count > 0, let current = calendar.dateInterval(of: bucket, for: now) else { return [] }
        var bars: [MeshBar] = []
        var start = current.start
        for _ in 0..<count {
            let end = calendar.dateInterval(of: bucket, for: start)?.end ?? start.addingTimeInterval(3600)
            bars.append(MeshBar(start: start, end: end, count: nil))
            guard let previous = calendar.date(byAdding: bucket, value: -1, to: start) else { break }
            start = calendar.dateInterval(of: bucket, for: previous)?.start ?? previous
        }
        bars.reverse()
        guard let first = bars.first?.start else { return bars }
        for hour in hours where hour.start >= first.addingTimeInterval(-3599) {
            guard let i = bars.lastIndex(where: { $0.start <= hour.start && hour.start < $0.end })
                    ?? bars.firstIndex(where: { hour.start < $0.start && hour.start.addingTimeInterval(3600) > $0.start }) else { continue }
            bars[i].count = (bars[i].count ?? 0) + (hour.counts[channel] ?? 0)
        }
        return bars
    }
}

/// One hour (UTC hour boundaries) in which DLChat was connected to the radio, and how many channel
/// messages it heard on each channel. Counts only: no text, no sender.
struct MeshHour: Codable, Equatable {
    var start: Date
    var counts: [UInt32: Int] = [:]

    static func start(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}

/// One bar of the message-count chart. `count` is nil when DLChat was not listening then.
struct MeshBar: Equatable, Identifiable {
    let start: Date
    let end: Date
    var count: Int?
    var id: Date { start }
}

/// Kept Meshtastic chats as their own sealed file in the Vault directory ("mesh.bin"), beside the main
/// store and under the same store key: Wipe deletes that key first, then the directory, so both go.
/// A separate file keeps a busy public channel from making every group-message read decode it.
@MainActor
final class MeshArchiveFile: MeshArchiveStore {
    static let name = "mesh.bin"
    private let vault: Vault

    init(vault: Vault) { self.vault = vault }

    func load() throws -> MeshArchive? {
        guard let data = try vault.readStore(named: Self.name) else { return nil }
        return try Self.decoder.decode(MeshArchive.self, from: data)
    }

    func save(_ archive: MeshArchive) throws {
        try vault.writeStore(try Self.encoder.encode(archive), named: Self.name)
    }

    func delete() { vault.removeStore(named: Self.name) }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
