import XCTest
@testable import DLChat

/// Keeping Meshtastic chats longer (opt-in), the caps, and the hourly counts behind the activity chart.
@MainActor
final class MeshArchiveTests: XCTestCase {
    private var suites: [String] = []
    private var vaults: [(Vault, URL)] = []
    override func tearDown() {
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }; suites = []
        for (vault, dir) in vaults { try? vault.wipe(); try? FileManager.default.removeItem(at: dir) }; vaults = []
    }

    private final class MemoryStore: MeshArchiveStore {
        var saved: MeshArchive?
        var saves = 0
        var failsToRead = false
        func load() throws -> MeshArchive? { if failsToRead { throw VaultError.keyMissing }; return saved }
        func save(_ archive: MeshArchive) throws { saved = archive; saves += 1 }
        func delete() { saved = nil }
    }

    private func text(_ s: String, at: Date, outgoing: Bool = false, id: UInt32 = 1, state: MeshText.State = .received) -> MeshText {
        MeshText(packetID: id, from: outgoing ? 0xA1 : 0xB2, text: s, at: at, outgoing: outgoing, isPrivate: false, hops: 0, state: state)
    }

    private func radio(_ node: UInt32, store: MeshArchiveStore) -> (MeshtasticModel, FakeRadio) {
        let suite = "dlchat.mesharchive.tests.\(UUID().uuidString)"
        suites.append(suite)
        let fake = FakeRadio(node: node)
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: MeshtasticModel.lawAcceptedKey)
        let mesh = MeshtasticModel(defaults: d, country: { "US" }, saveDelay: .milliseconds(1)) { fake }
        mesh.useArchive(store)
        return (mesh, fake)
    }

    private func pair(_ a: (MeshtasticModel, FakeRadio), _ b: (MeshtasticModel, FakeRadio)) {
        a.1.air = [a.1, b.1]; b.1.air = a.1.air
        for (mesh, _) in [a, b] { mesh.setOn(true); mesh.choose(mesh.radios[0]) }
    }

    // MARK: Archive

    func testCapsPerConversationAndInTotal() {
        var archive = MeshArchive()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<(MeshArchive.maxPerConversation + 10) {
            archive.append(text("c\(i)", at: start.addingTimeInterval(Double(i))), to: .channel(0))
        }
        XCTAssertEqual(archive.texts[.channel(0)]?.count, MeshArchive.maxPerConversation)
        XCTAssertEqual(archive.texts[.channel(0)]?.first?.text, "c10", "the oldest go first")
        for n in 1...5 {
            for i in 0..<MeshArchive.maxPerConversation {
                archive.append(text("d\(n)-\(i)", at: start.addingTimeInterval(Double(n * 10_000 + i))), to: .direct(UInt32(n)))
            }
        }
        XCTAssertEqual(archive.totalTexts, MeshArchive.maxTotal)
        XCTAssertNil(archive.texts[.channel(0)], "the oldest conversation's messages went first")
    }

    func testPurgeDropsOnlyWhatIsOlderThanTheSetting() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        var archive = MeshArchive()
        archive.append(text("old", at: now.addingTimeInterval(-2 * 86_400)), to: .channel(0))
        archive.append(text("new", at: now.addingTimeInterval(-3600)), to: .channel(0))
        archive.counted(channel: 0, at: now.addingTimeInterval(-2 * 86_400))
        archive.counted(channel: 0, at: now.addingTimeInterval(-3600))
        for keep in [Retention.off, .forever] {
            var a = archive; a.keep = keep; a.purge(now: now)
            XCTAssertEqual(a.totalTexts, 2, "\(keep) drops nothing by age")
        }
        archive.keep = .day
        archive.purge(now: now)
        XCTAssertEqual(archive.texts[.channel(0)]?.map(\.text), ["new"])
        XCTAssertEqual(archive.hours.count, 1)
    }

    func testHourlySeriesTellsNotListeningFromSilence() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_800_000_000 + 1800)  // half past an hour
        var archive = MeshArchive()
        archive.listened(at: now.addingTimeInterval(-3 * 3600))        // connected, nothing heard
        archive.counted(channel: 0, at: now.addingTimeInterval(-3600))
        archive.counted(channel: 0, at: now.addingTimeInterval(-3500))
        archive.counted(channel: 1, at: now.addingTimeInterval(-3500))  // another channel
        archive.counted(channel: 0, at: now)
        let bars = archive.series(channel: 0, bucket: .hour, count: 4, now: now, calendar: utc)
        XCTAssertEqual(bars.map(\.count), [0, nil, 2, 1])
        XCTAssertEqual(bars.last?.start, MeshHour.start(of: now))
        let days = archive.series(channel: 0, bucket: .day, count: 2, now: now, calendar: utc)
        XCTAssertEqual(days.last?.count, 3)
    }

    // MARK: Model

    func testOffByDefaultSavesNothing() async throws {
        let store = MemoryStore()
        let a = radio(0xA1, store: store), b = radio(0xB2, store: store)
        pair(a, b)
        XCTAssertEqual(b.0.keep, .off)
        XCTAssertNil(a.0.sendText("hello mesh", in: .channel(0)))
        try await Task.sleep(for: .milliseconds(50))
        b.0.saveNow()
        XCTAssertEqual(store.saves, 0)
        XCTAssertNil(store.saved)
        let bars = b.0.archive.series(channel: 0, bucket: .hour, count: 1, now: Date())
        XCTAssertEqual(bars.last?.count, 1, "counted in memory for this session")
    }

    func testKeptChatsComeBackAfterRelaunchAndOffErasesThem() async throws {
        let store = MemoryStore(), other = MemoryStore()
        let a = radio(0xA1, store: other), b = radio(0xB2, store: store)
        pair(a, b)
        b.0.setKeep(.week)
        XCTAssertEqual(store.saved?.keep, .week)
        XCTAssertNil(a.0.sendText("kept on b", in: .channel(0)))
        XCTAssertNil(b.0.sendText("going out", in: .channel(0)))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.saved?.texts[.channel(0)]?.map(\.text), ["kept on b", "going out"], "saved shortly after")
        XCTAssertNil(other.saved, "a's own setting is still off")

        let relaunched = radio(0xB2, store: store)
        XCTAssertEqual(relaunched.0.keep, .week)
        let list = try XCTUnwrap(relaunched.0.texts[.channel(0)])
        XCTAssertEqual(list.map(\.text), ["kept on b", "going out"])
        guard case .failed = list[1].state else { return XCTFail("a send nothing confirmed cannot stay 'sending'") }
        XCTAssertEqual(relaunched.0.archive.series(channel: 0, bucket: .hour, count: 1, now: Date()).last?.count, 1)

        relaunched.0.setKeep(.off)
        XCTAssertNil(store.saved, "turning it off deletes the saved chats at once")
    }

    func testAReadFailureNeverOverwritesWhatWasKept() async throws {
        let store = MemoryStore()
        var kept = MeshArchive(); kept.keep = .forever
        kept.append(text("from last week", at: Date().addingTimeInterval(-5 * 86_400)), to: .channel(0))
        store.saved = kept
        store.failsToRead = true  // the iPhone is locked
        let a = radio(0xA1, store: MemoryStore()), b = radio(0xB2, store: store)
        pair(a, b)
        XCTAssertNil(a.0.sendText("while locked", in: .channel(0)))
        b.0.saveNow()
        XCTAssertEqual(store.saves, 0)
        store.failsToRead = false
        b.0.purgeExpired()  // returning to the app reads it again
        XCTAssertEqual(b.0.texts[.channel(0)]?.map(\.text), ["from last week", "while locked"])
        XCTAssertEqual(b.0.keep, .forever)
    }

    func testWipeResetsTheSettingAndVaultWipeErasesTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mesh-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        vaults.append((vault, dir))
        let file = MeshArchiveFile(vault: vault)
        let a = radio(0xA1, store: MemoryStore()), b = radio(0xB2, store: file)
        pair(a, b)
        b.0.setKeep(.forever)
        XCTAssertNil(a.0.sendText("secret-ish", in: .channel(0)))
        b.0.saveNow()
        let onDisk = try Data(contentsOf: vault.storeURL(named: MeshArchiveFile.name))
        XCTAssertNil(onDisk.range(of: Data("secret-ish".utf8)), "sealed, not plain text")
        XCTAssertEqual(try file.load()?.texts[.channel(0)]?.map(\.text), ["secret-ish"])

        b.0.wipe()
        XCTAssertEqual(b.0.keep, .off)
        XCTAssertTrue(b.0.texts.isEmpty)
        XCTAssertTrue(b.0.archive.hours.isEmpty)
        try vault.wipe()
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.storeURL(named: MeshArchiveFile.name).path))
    }
}
