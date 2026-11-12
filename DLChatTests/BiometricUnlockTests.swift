import XCTest
@testable import DLChat

/// Face ID unlock on top of the PIN. A fake stands in for the Face ID Keychain item, which needs a real face.
@MainActor
final class BiometricUnlockTests: XCTestCase {
    private final class FakeBiometrics: BiometricKey {
        var kind: String? = "Face ID"
        var stored: Data?
        /// What the next Face ID sheet ends in; nil means a match (the stored token comes back).
        var next: BiometricRead?
        var reads = 0
        func save(_ token: Data) throws { stored = token }
        func read(reason: String) async -> BiometricRead {
            reads += 1
            if let next { return next }
            return stored.map(BiometricRead.token) ?? .invalidated
        }
        func remove() { stored = nil }
    }

    private var cleanup: [() -> Void] = []
    private var wipes = 0

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-bio-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    private func makeLock(_ vault: Vault, _ bio: FakeBiometrics) -> AppLock {
        AppLock(vault: vault, rounds: 1_000, wipe: { self.wipes += 1; try? vault.wipe(); return true }, biometrics: bio)
    }

    func testOffByDefaultAndNeedsThePINToTurnOn() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertFalse(lock.biometricsOn, "Face ID is off until turned on")
        XCTAssertEqual(lock.turnOnBiometrics(pin: "111111"), .wrongPIN)
        XCTAssertNil(bio.stored)
        XCTAssertNil(lock.setDuressPIN("999999"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "999999"), .wrongPIN, "the duress PIN does not turn it on")
        XCTAssertEqual(wipes, 0, "and does not wipe from Safety")
        bio.kind = nil
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .unavailable)
        bio.kind = "Face ID"
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        XCTAssertTrue(lock.biometricsOn)
        XCTAssertEqual(bio.stored?.count, 32)

        // Survives a relaunch, which starts locked; a Face ID match unlocks.
        let relaunched = makeLock(vault, bio)
        XCTAssertTrue(relaunched.biometricsOn)
        XCTAssertTrue(relaunched.isLocked)
        let opened = await relaunched.unlockWithBiometrics()
        XCTAssertTrue(opened)
        XCTAssertFalse(relaunched.isLocked)
    }

    func testCancelKeepsThePINPadAndIsNotAskedAgainUntilNextLock() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        lock.lock()
        XCTAssertFalse(lock.biometricAskedThisLock)
        bio.next = .declined
        let opened = await lock.unlockWithBiometrics()
        XCTAssertFalse(opened)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.biometricsOn, "a cancel or failed face does not turn Face ID off")
        XCTAssertTrue(lock.biometricAskedThisLock)
        XCTAssertEqual(lock.enter("246810"), .unlocked, "the PIN still opens it")
        lock.lock()
        XCTAssertFalse(lock.biometricAskedThisLock)
    }

    func testFacesChangedNeedsThePINAndTurningOnAgain() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        lock.lock()
        bio.stored = nil  // iOS drops a biometryCurrentSet item when a face is added or removed.
        let opened = await lock.unlockWithBiometrics()
        XCTAssertFalse(opened)
        XCTAssertTrue(lock.isLocked)
        XCTAssertFalse(lock.biometricsOn)
        XCTAssertTrue(lock.biometricsInvalidated)
        XCTAssertEqual(lock.enter("246810"), .unlocked)
        XCTAssertFalse(lock.biometricsInvalidated)
        XCTAssertFalse(makeLock(vault, bio).biometricsOn, "stays off after a relaunch")
    }

    func testATokenThatDoesNotMatchIsRefused() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        lock.lock()
        bio.next = .token(Data(repeating: 7, count: 32))
        let opened = await lock.unlockWithBiometrics()
        XCTAssertFalse(opened)
        XCTAssertTrue(lock.isLocked)
        XCTAssertFalse(lock.biometricsOn)
    }

    /// Launch and return: Face ID is asked for before the call returns, once per lock, one sheet at a time.
    func testAskingStartsAtOnceOncePerLockAndNeverTwoSheets() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        lock.lock()
        lock.askForBiometricsIfDue()
        XCTAssertTrue(lock.biometricPromptOpen, "the sheet is asked for before the call returns")
        XCTAssertTrue(lock.biometricAskedThisLock)
        let stacked = await lock.unlockWithBiometrics()
        XCTAssertFalse(stacked, "a tap on the button while the sheet is up does not ask again")
        for _ in 0..<500 where lock.isLocked { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(lock.isLocked, "the match unlocks")
        XCTAssertFalse(lock.biometricPromptOpen)
        XCTAssertEqual(bio.reads, 1)

        lock.lock()
        bio.next = .declined
        lock.askForBiometricsIfDue()
        for _ in 0..<500 where lock.biometricPromptOpen { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(lock.isLocked)
        XCTAssertEqual(bio.reads, 2)
        lock.askForBiometricsIfDue()
        XCTAssertFalse(lock.biometricPromptOpen, "after a cancel it is not asked again on its own until the next lock")
        XCTAssertEqual(lock.enter("246810"), .unlocked)
    }

    func testNothingIsAskedWhenOffOrUnlocked() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        lock.lock()
        let whileOff = await lock.unlockWithBiometrics()
        XCTAssertFalse(whileOff)
        XCTAssertEqual(lock.enter("246810"), .unlocked)
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        let whileOpen = await lock.unlockWithBiometrics()
        XCTAssertFalse(whileOpen)
        XCTAssertEqual(bio.reads, 0)
    }

    func testDuressPINAndWipeClearFaceID() throws {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        XCTAssertNil(lock.setDuressPIN("999999"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)
        lock.lock()
        XCTAssertEqual(lock.enter("999999"), .unlocked)
        XCTAssertEqual(wipes, 1)
        XCTAssertFalse(lock.biometricsOn)
        XCTAssertNil(bio.stored)
        XCTAssertNil(try vault.secret(account: "lock.4"))

        XCTAssertNil(lock.setPIN("135790"))
        XCTAssertEqual(lock.turnOnBiometrics(pin: "135790"), .on)
        lock.removePINs()
        XCTAssertFalse(lock.biometricsOn)
        XCTAssertNil(bio.stored)
        XCTAssertNil(try vault.secret(account: "lock.4"))
    }

    /// The lock screen's cover (no PIN pad) shows only while Face ID has yet to answer; any "no" brings the pad.
    func testCoverHidesThePadOnlyUntilFaceIDAnswers() async {
        let vault = makeVault()
        let bio = FakeBiometrics()
        let lock = makeLock(vault, bio)
        XCTAssertNil(lock.setPIN("246810"))
        lock.lock()
        XCTAssertFalse(LockView.coverHidesPad(lock, pinInstead: false), "Face ID off: the pad shows at once")
        XCTAssertTrue(lock.enter("246810") == .unlocked)
        XCTAssertEqual(lock.turnOnBiometrics(pin: "246810"), .on)

        lock.lock()
        XCTAssertTrue(LockView.coverHidesPad(lock, pinInstead: false), "locked with Face ID on, not asked yet")
        XCTAssertFalse(LockView.coverHidesPad(lock, pinInstead: true), "Use PIN shows the pad without waiting")
        bio.next = .declined
        let opened = await lock.unlockWithBiometrics()
        XCTAssertFalse(opened)
        XCTAssertTrue(lock.isLocked)
        XCTAssertFalse(LockView.coverHidesPad(lock, pinInstead: false), "Face ID said no: the pad shows")

        lock.lock()
        bio.next = .invalidated
        _ = await lock.unlockWithBiometrics()
        XCTAssertFalse(LockView.coverHidesPad(lock, pinInstead: false), "faces changed: Face ID is off, the pad shows")
        XCTAssertEqual(lock.enter("246810"), .unlocked, "and the PIN still opens DLChat")
    }
}
