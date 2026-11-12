import DLCore
import XCTest
@testable import DLChat

@MainActor
final class AppLockTests: XCTestCase {
    private var cleanup: [() -> Void] = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var wipes = 0

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    /// By default the monotonic clock follows the wall clock; tests that move only the wall clock pass `uptime`.
    private func makeLock(_ vault: Vault, uptime: (() -> TimeInterval)? = nil, wipe: (() -> Bool)? = nil) -> AppLock {
        AppLock(
            vault: vault, rounds: 1_000, now: { self.clock },
            uptime: uptime ?? { self.clock.timeIntervalSince1970 - 1_800_000_000 },
            wipe: wipe ?? { self.wipes += 1; return true })
    }

    func testPINRulesAndUnlock() {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertFalse(lock.isLocked)
        XCTAssertTrue(lock.mustCreatePIN, "a phone with no PIN must create one first")
        XCTAssertEqual(lock.setPIN("12345"), .wrongLength)
        XCTAssertEqual(lock.setPIN("12345a"), .notDigits)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertTrue(lock.hasPIN)
        XCTAssertFalse(lock.mustCreatePIN)
        XCTAssertFalse(lock.coversApp)

        // A new object on the same vault is a relaunch: it starts locked.
        let relaunched = makeLock(vault)
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertEqual(relaunched.enter("246811"), .wrong(failures: 1))
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertEqual(relaunched.enter("246810"), .unlocked)
        XCTAssertFalse(relaunched.isLocked)
        relaunched.lock()
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertEqual(wipes, 0)
    }

    func testPINIsStoredAsAHashNotTheDigits() throws {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertNil(lock.setPIN("135790"))
        let stored = try XCTUnwrap(try vault.secret(account: "lock.1"))
        XCTAssertEqual(stored.count, 48)
        XCTAssertNil(stored.range(of: Data("135790".utf8)))
    }

    func testUnreadableKeychainKeepsTheAppLockedUntilItCanBeRead() {
        struct Unreadable: Error {}
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        var readable = false
        let lock = AppLock(
            vault: vault, rounds: 1_000, now: { self.clock }, wipe: { self.wipes += 1; return true },
            readSecret: { account in
                if !readable { throw Unreadable() }
                return try vault.secret(account: account)
            })
        XCTAssertTrue(lock.isLocked, "a read error must not open the app")
        XCTAssertTrue(lock.hasPIN)
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 5))
        XCTAssertTrue(lock.isLocked)
        readable = true
        XCTAssertEqual(lock.enter("000000"), .wrong(failures: 1))
        XCTAssertEqual(lock.enter("246810"), .unlocked)
        XCTAssertFalse(lock.isLocked)
    }

    func testFailuresDelayAndTheDelaySurvivesRelaunch() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        let lock = makeLock(vault)
        XCTAssertEqual(lock.enter("000000"), .wrong(failures: 1))
        XCTAssertEqual(lock.enter("000000"), .wrong(failures: 2))
        XCTAssertEqual(lock.enter("000000"), .waiting(seconds: 30))

        // Even the right PIN is refused while waiting, also after a kill and relaunch.
        let relaunched = makeLock(vault)
        XCTAssertEqual(relaunched.enter("246810"), .waiting(seconds: 30))
        clock.addTimeInterval(31)
        XCTAssertEqual(relaunched.enter("000000"), .waiting(seconds: 60))
        clock.addTimeInterval(61)
        XCTAssertEqual(relaunched.enter("246810"), .unlocked)
        // A right PIN clears the count.
        relaunched.lock()
        XCTAssertEqual(relaunched.enter("000000"), .wrong(failures: 1))
    }

    func testDelayScheduleIsCapped() {
        XCTAssertEqual(AppLock.delay(afterFailures: 2), 0)
        XCTAssertEqual(AppLock.delay(afterFailures: 3), 30)
        XCTAssertEqual(AppLock.delay(afterFailures: 4), 60)
        XCTAssertEqual(AppLock.delay(afterFailures: 40), 3600)
    }

    func testDuressPINWipesAndLooksLikeAnUnlock() {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertEqual(lock.setDuressPIN("111111"), .needsPIN)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertEqual(lock.setDuressPIN("246810"), .sameAsPIN)
        XCTAssertNil(lock.setDuressPIN("999999"))
        XCTAssertEqual(lock.setPIN("999999"), .sameAsPIN)

        let relaunched = makeLock(vault)
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertEqual(relaunched.enter("999999"), .unlocked)
        XCTAssertFalse(relaunched.isLocked)
        XCTAssertEqual(wipes, 1)
        XCTAssertFalse(relaunched.hasPIN)
        // Straight after the duress unlock nothing asks for a new PIN, so it looks like a normal unlock...
        XCTAssertFalse(relaunched.mustCreatePIN)
        XCTAssertFalse(relaunched.coversApp)
        // ...but the next time the app is left, a new PIN is required.
        relaunched.lock()
        XCTAssertTrue(relaunched.mustCreatePIN)
        XCTAssertTrue(relaunched.coversApp)
        XCTAssertFalse(relaunched.isLocked)
    }

    func testPINCanBeFourSixOrEightDigits() {
        let vault = makeVault()
        let lock = makeLock(vault)
        for bad in ["123", "12345", "1234567", "123456789"] { XCTAssertEqual(lock.setPIN(bad), .wrongLength, bad) }
        for good in ["1357", "135790", "13579024"] {
            XCTAssertNil(lock.setPIN(good), good)
            let relaunched = makeLock(vault)
            XCTAssertEqual(relaunched.enter(good), .unlocked, good)
        }
        XCTAssertEqual(lock.setDuressPIN("99999"), .wrongLength)
        XCTAssertNil(lock.setDuressPIN("9999"))
    }

    func testNewInstallCannotUseTheAppUntilAPINIsSet() {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertTrue(lock.coversApp)
        XCTAssertFalse(lock.isLocked)
        // Leaving and coming back does not skip it.
        lock.lock()
        XCTAssertTrue(lock.mustCreatePIN)
        XCTAssertTrue(makeLock(vault).mustCreatePIN, "a relaunch still asks")
        XCTAssertEqual(lock.setPIN("12345"), .wrongLength)
        XCTAssertTrue(lock.coversApp)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertFalse(lock.coversApp)
        // From then on every launch and every return from the background asks for the PIN.
        let relaunched = makeLock(vault)
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertFalse(relaunched.mustCreatePIN)
        XCTAssertEqual(relaunched.enter("246810"), .unlocked)
        relaunched.lock()
        XCTAssertTrue(relaunched.isLocked)
    }

    func testUnreadableKeychainWithNoPINAsksForOneOnceReadable() {
        struct Unreadable: Error {}
        let vault = makeVault()
        var readable = false
        let lock = AppLock(
            vault: vault, rounds: 1_000, now: { self.clock }, wipe: { self.wipes += 1; return true },
            readSecret: { account in
                if !readable { throw Unreadable() }
                return try vault.secret(account: account)
            })
        XCTAssertTrue(lock.isLocked)
        XCTAssertFalse(lock.mustCreatePIN)
        readable = true
        XCTAssertEqual(lock.enter("000000"), .unlocked, "no PIN to check, and no wrong try recorded")
        XCTAssertFalse(lock.isLocked)
        XCTAssertTrue(lock.mustCreatePIN)
        XCTAssertTrue(lock.coversApp)
    }

    func testDuressPINStillWorksAfterAWrongTry() {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertNil(lock.setDuressPIN("999999"))
        _ = lock.enter("000000")
        XCTAssertEqual(lock.enter("999999"), .unlocked)
        XCTAssertEqual(wipes, 1)
    }

    func testFailedDuressWipeStaysLockedKeepsThePINsAndCanBeRetried() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        XCTAssertNil(makeLock(vault).setDuressPIN("999999"))
        var works = false
        var tries = 0
        let lock = makeLock(vault) { tries += 1; return works }
        XCTAssertEqual(lock.enter("999999"), .wipeFailed)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.hasPIN)
        // The real PIN still opens, and a failed wipe did not count as a wrong try.
        XCTAssertEqual(lock.enter("000000"), .wrong(failures: 1))
        works = true
        XCTAssertEqual(lock.enter("999999"), .unlocked)
        XCTAssertEqual(tries, 2)
        XCTAssertFalse(lock.hasPIN)
    }

    func testDuressPINWorksDuringAWrongPINWait() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        XCTAssertNil(makeLock(vault).setDuressPIN("999999"))
        let lock = makeLock(vault)
        for _ in 0..<3 { _ = lock.enter("000000") }
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 30))
        XCTAssertEqual(lock.enter("999999"), .unlocked)
        XCTAssertEqual(wipes, 1)
        XCTAssertFalse(lock.isLocked)
    }

    func testClockSetBackStartsTheWaitAgain() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        let lock = makeLock(vault)
        for _ in 0..<3 { _ = lock.enter("000000") }
        clock.addTimeInterval(-86_400 * 365)
        // A full wait from the new time, saved, not a wait of a year and not an open door.
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 30))
        clock.addTimeInterval(29)
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 1))
        clock.addTimeInterval(2)
        XCTAssertEqual(lock.enter("246810"), .unlocked)
    }

    func testClockSetForwardDoesNotShortenTheWait() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        let boot = 5_000.0
        var up = boot
        let lock = makeLock(vault, uptime: { up })
        for _ in 0..<3 { _ = lock.enter("000000") }
        clock.addTimeInterval(3_600)
        up += 10
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 20))
        up += 21
        XCTAssertEqual(lock.enter("246810"), .unlocked)
    }

    func testRestartPlusClockSetForwardDoesNotSkipTheWait() {
        let vault = makeVault()
        XCTAssertNil(makeLock(vault).setPIN("246810"))
        var up = 5_000.0
        let lock = makeLock(vault, uptime: { up })
        for _ in 0..<3 { _ = lock.enter("000000") }
        // The iPhone restarted (its boot clock starts over) and the date was set an hour ahead.
        up = 12
        clock.addTimeInterval(3_600)
        XCTAssertEqual(lock.enter("246810"), .waiting(seconds: 30))
        up += 31
        clock.addTimeInterval(31)
        XCTAssertEqual(lock.enter("246810"), .unlocked)
    }

    func testKeychainLooksTheSameWithOrWithoutADuressPIN() throws {
        let plain = makeVault(), withDuress = makeVault()
        XCTAssertNil(makeLock(plain).setPIN("246810"))
        let lock = makeLock(withDuress)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertNil(lock.setDuressPIN("999999"))
        for vault in [plain, withDuress] {
            XCTAssertEqual(try vault.secret(account: "lock.1")?.count, 48)
            XCTAssertEqual(try vault.secret(account: "lock.2")?.count, 48)
        }
        // The random filler matches no PIN, and the real PIN still opens.
        let relaunched = makeLock(plain)
        XCTAssertEqual(relaunched.enter("999999"), .wrong(failures: 1))
        XCTAssertEqual(relaunched.enter("246810"), .unlocked)
        XCTAssertEqual(wipes, 0)
    }

    func testOldItemNamesAreMovedAndStillWork() throws {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertNil(lock.setDuressPIN("999999"))
        // As an older build stored them.
        try vault.setSecret(try XCTUnwrap(vault.secret(account: "lock.1")), account: "lock.pin")
        try vault.setSecret(try XCTUnwrap(vault.secret(account: "lock.2")), account: "lock.duress")
        try vault.removeSecret(account: "lock.1"); try vault.removeSecret(account: "lock.2")

        let relaunched = makeLock(vault)
        XCTAssertNil(try vault.secret(account: "lock.pin"))
        XCTAssertNil(try vault.secret(account: "lock.duress"))
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertEqual(relaunched.enter("999999"), .unlocked)
        XCTAssertEqual(wipes, 1)
    }

    func testRemovingPINsUnlocksAndClearsEverything() throws {
        let vault = makeVault()
        let lock = makeLock(vault)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertNil(lock.setDuressPIN("999999"))
        lock.removePINs()
        XCTAssertFalse(lock.hasPIN)
        XCTAssertNil(try vault.secret(account: "lock.1"))
        XCTAssertNil(try vault.secret(account: "lock.2"))
        XCTAssertFalse(lock.mustCreatePIN, "not straight after the wipe")
        XCTAssertFalse(makeLock(vault).isLocked)
        XCTAssertTrue(makeLock(vault).mustCreatePIN, "the next launch asks for a new PIN")
    }
}

@MainActor
final class PanicWipeTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-panic-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    func testWipeLeavesNothingAndNoDraftIsWrittenAfterwards() async throws {
        let vault = makeVault()
        let groups = GroupModel(vault: vault)
        try groups.save(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        compose.text = "marker plaintext zebra"
        compose.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.storeURL.path))

        compose.discard()
        XCTAssertTrue(groups.wipeEverything())

        XCTAssertTrue(groups.groups.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.storeURL.path))
        XCTAssertNil(try vault.secret(account: Vault.storeKeyAccount))
        XCTAssertEqual(compose.text, "")

        // A pending autosave and the group change that follows must not write a new store.
        try await Task.sleep(for: .milliseconds(600))
        compose.syncGroup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.storeURL.path))
        XCTAssertTrue(groups.keySets().isEmpty)
    }
}

@MainActor
final class DuressFlagTests: XCTestCase {
    func testDuressFlagReachesTheReceiverAndNormalMessagesCarryNone() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-duress-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        defer { try? vault.wipe() }
        let groups = GroupModel(vault: vault)
        try groups.save(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let keys = try XCTUnwrap(try groups.keys(for: XCTUnwrap(groups.groups.first)))
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        compose.text = "all clear here"

        XCTAssertTrue(compose.prepareWords())
        XCTAssertEqual(Receiver.read(words: compose.words, trying: [keys])?.duress, false)

        compose.duress = true
        XCTAssertTrue(compose.prepareWords())
        let message = try XCTUnwrap(Receiver.read(words: compose.words, trying: [keys]))
        XCTAssertTrue(message.duress)
        XCTAssertEqual(message.text, "all clear here")
        // The flag does not change how many words are said.
        XCTAssertEqual(compose.words.count, compose.count)
    }
}
