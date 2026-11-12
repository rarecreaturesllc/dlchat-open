import CommonCrypto
import CryptoKit
import Foundation
import Observation

/// App PIN and duress PIN. The PIN is required: a phone with no PIN (first launch, or an install from
/// before the PIN was required) is asked to create one before anything else shows, and the app locks
/// every time it goes to the background. Both are stored as a salted PBKDF2 hash in the Keychain, next to the
/// secrets they guard, so a wipe removes them too. Wrong guesses are counted in the Keychain and
/// delay the next try, so a kill and relaunch does not reset the delay.
///
/// Typing the duress PIN wipes everything through `wipe` and then reports `.unlocked`, exactly as a
/// correct PIN does, so the screen cannot tell the two apart. If the wipe fails the app stays locked,
/// the PINs are kept and `.wipeFailed` is reported, so the person can try again.
///
/// Face ID is an optional shortcut on top of the PIN, never instead of it. Turning it on needs the PIN.
/// It saves a random token in a Keychain item that iOS only releases after a Face ID match with the faces
/// enrolled at that moment, and a hash of that token in an ordinary item; unlocking reads the token through
/// Face ID and checks it against the hash. If faces change, the item is gone and the PIN is needed again.
/// Face ID can never trigger the duress wipe: that only happens by typing the duress PIN.
@MainActor
@Observable
final class AppLock {
    enum Entry: Equatable {
        case unlocked
        case wrong(failures: Int)
        /// Too many wrong tries: the PIN is not checked until this many seconds have passed.
        case waiting(seconds: Int)
        /// The duress PIN was typed but the wipe did not finish. Still locked; nothing was removed.
        case wipeFailed
    }

    enum SetupProblem: Equatable {
        case notDigits
        case wrongLength
        case sameAsPIN
        case needsPIN

        var message: String {
            switch self {
            case .notDigits: return "Use digits only."
            case .wrongLength: return "Use 4, 6 or 8 digits."
            case .sameAsPIN: return "The duress PIN must differ from the PIN."
            case .needsPIN: return "Set a PIN first."
            }
        }
    }

    /// The person picks the PIN length when creating it. 6 is the default; 4 is allowed but easier to guess.
    nonisolated static let allowedLengths = [4, 6, 8]
    nonisolated static let defaultLength = 6

    private(set) var isLocked: Bool
    private(set) var hasPIN: Bool
    /// No PIN yet: the create-a-PIN screen covers the app until one is saved. After a wipe this waits until
    /// the app is next left or relaunched, so a duress unlock looks the same as a normal one in the moment.
    private(set) var mustCreatePIN: Bool

    /// Face ID (or Touch ID) unlock is turned on. Off until the person turns it on in Safety with the PIN.
    private(set) var biometricsOn: Bool
    /// Set when the Face ID item was found gone (faces changed): the lock screen says why the PIN is needed.
    private(set) var biometricsInvalidated = false
    /// Face ID is asked for on its own only once each time the app locks, so a cancel is not followed by another prompt.
    private(set) var biometricAskedThisLock = false
    /// True from asking Face ID until it answers. Its sheet makes DLChat inactive for a moment, and the app
    /// does not treat that as leaving (nothing is stopped and restarted around it).
    private(set) var biometricPromptOpen = false

    /// Whether the lock window (enter or create a PIN) covers the app.
    var coversApp: Bool { isLocked || mustCreatePIN }

    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let rounds: UInt32
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let wipe: () -> Bool
    @ObservationIgnored private let readSecret: (String) throws -> Data?
    @ObservationIgnored let biometrics: BiometricKey
    /// True when the Keychain could not be read at start (for example, launched while the phone is locked). The app stays locked until a read works.
    private var unreadable = false

    // Neutral names, and the duress slot always holds 48 bytes once a PIN is set (random when there is
    // no duress PIN), so the Keychain looks the same whether or not a duress PIN exists.
    private static let pinAccount = "lock.1"
    private static let duressAccount = "lock.2"
    private static let failureAccount = "lock.3"
    /// SHA-256 of the token held behind Face ID (`KeychainBiometricKey.account` is the item itself).
    private static let biometricHashAccount = "lock.4"
    /// Names used before 2026-11-08, moved to the neutral ones at launch.
    private static let legacyAccounts = [("lock.pin", pinAccount), ("lock.duress", duressAccount), ("lock.failures", failureAccount)]

    private struct Failures: Codable {
        var count = 0
        var until: Date?
        /// Wall time of the last wrong try. A clock earlier than this has been set back.
        var last: Date?
        /// Length of the current wait and the monotonic clock at the last wrong try. The monotonic clock
        /// keeps counting when the wall clock is moved, so a forward jump cannot shorten the wait.
        var seconds: TimeInterval?
        var uptimeAtLast: TimeInterval?
    }

    /// `rounds` is lowered by tests only; `wipe` erases everything, resets the screens and says whether it worked.
    init(
        vault: Vault, rounds: UInt32 = 200_000, now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wipe: @escaping () -> Bool, readSecret: ((String) throws -> Data?)? = nil,
        biometrics: BiometricKey? = nil
    ) {
        self.vault = vault
        self.rounds = rounds
        self.now = now
        self.uptime = uptime
        self.wipe = wipe
        let read = readSecret ?? { try vault.secret(account: $0) }
        self.readSecret = read
        self.biometrics = biometrics ?? KeychainBiometricKey(service: vault.service)
        Self.moveLegacyItems(vault)
        // A read error is not "no PIN": fail closed so an unreadable Keychain cannot open the app.
        let pin = Self.present(Self.pinAccount, read)
        hasPIN = pin ?? true
        isLocked = pin ?? true
        mustCreatePIN = pin == false
        unreadable = pin == nil
        biometricsOn = pin == true && Self.present(Self.biometricHashAccount, read) == true
        if pin == true, Self.present(Self.duressAccount, read) == false { fillDuressSlot() }
    }

    private static func moveLegacyItems(_ vault: Vault) {
        for (old, new) in legacyAccounts {
            guard let data = (try? vault.secret(account: old)) ?? nil else { continue }
            if (try? vault.setSecret(data, account: new)) != nil { try? vault.removeSecret(account: old) }
        }
    }

    /// Random bytes in the duress slot, shaped like a stored hash. No PIN can match them.
    private func fillDuressSlot() {
        var bytes = Data(count: 48)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 48, $0.baseAddress!) }
        if status == errSecSuccess { try? vault.setSecret(bytes, account: Self.duressAccount) }
    }

    /// nil means the Keychain could not be read.
    private static func present(_ account: String, _ read: (String) throws -> Data?) -> Bool? {
        do { return try read(account) != nil } catch { return nil }
    }

    private func refreshIfUnreadable() {
        guard unreadable, let pin = Self.present(Self.pinAccount, readSecret) else { return }
        unreadable = false
        hasPIN = pin
        if !pin { isLocked = false; mustCreatePIN = true }
    }

    // MARK: Delay

    /// Free tries first, then 30 seconds doubling each time, capped at an hour.
    static func delay(afterFailures count: Int) -> TimeInterval {
        guard count >= 3 else { return 0 }
        return min(30 * pow(2, Double(count - 3)), 3600)
    }

    // MARK: Unlock

    /// Locks again when the app goes to the background. Without a PIN (only possible right after a wipe)
    /// it asks for a new one instead.
    func lock() {
        if hasPIN { isLocked = true } else if !unreadable { mustCreatePIN = true }
        biometricAskedThisLock = false
    }

    func enter(_ pin: String) -> Entry {
        refreshIfUnreadable()
        if unreadable { return .waiting(seconds: 5) }
        // The Keychain became readable and holds no PIN: nothing to check; the screen moves on to creating one.
        guard hasPIN else { return .unlocked }
        var failures = loadFailures()
        // Both hashes are always computed, so timing does not tell the duress PIN from the real one. The
        // duress PIN is checked before the wait: it is the one PIN someone under pressure must be able to use.
        let duress = matches(pin, account: Self.duressAccount)
        let real = matches(pin, account: Self.pinAccount)
        if duress {
            guard wipe() else { return .wipeFailed }
            // The wipe deleted every Keychain item, the Face ID one included; this makes sure of it.
            turnOffBiometrics()
            hasPIN = false
            isLocked = false
            return .unlocked
        }
        let remaining = remainingWait(&failures)
        if remaining > 0 { return .waiting(seconds: Int(remaining.rounded(.up))) }
        if real {
            try? vault.removeSecret(account: Self.failureAccount)
            isLocked = false
            biometricsInvalidated = false
            return .unlocked
        }
        failures.count += 1
        let wait = Self.delay(afterFailures: failures.count)
        let current = now()
        failures.until = wait > 0 ? current.addingTimeInterval(wait) : nil
        failures.last = current
        failures.seconds = wait
        failures.uptimeAtLast = uptime()
        saveFailures(failures)
        return wait > 0 ? .waiting(seconds: Int(wait)) : .wrong(failures: failures.count)
    }

    /// Seconds left to wait. A wall clock set back before the last wrong try starts the full wait again
    /// (and saves that), within one boot the monotonic clock can only lengthen the wait, and a restart of
    /// the iPhone starts the full wait again too.
    private func remainingWait(_ failures: inout Failures) -> TimeInterval {
        guard let until = failures.until else { return 0 }
        let current = now()
        if let last = failures.last, current < last {
            let wait = Self.delay(afterFailures: failures.count)
            failures.until = current.addingTimeInterval(wait)
            failures.last = current
            failures.seconds = wait
            failures.uptimeAtLast = uptime()
            saveFailures(failures)
            return wait
        }
        var left = until.timeIntervalSince(current)
        if let seconds = failures.seconds, let at = failures.uptimeAtLast {
            if uptime() >= at {
                left = max(left, seconds - (uptime() - at))
            } else {
                // The iPhone restarted since the wrong try, so only the wall clock says how long ago it was,
                // and that can be set forward by hand. The full wait starts again, once (this saves the new boot's clock).
                let wait = Self.delay(afterFailures: failures.count)
                failures.until = current.addingTimeInterval(wait)
                failures.last = current
                failures.seconds = wait
                failures.uptimeAtLast = uptime()
                saveFailures(failures)
                return wait
            }
        }
        return max(left, 0)
    }

    // MARK: Setup

    func setPIN(_ pin: String) -> SetupProblem? {
        if let problem = Self.check(pin) { return problem }
        if matches(pin, account: Self.duressAccount) { return .sameAsPIN }
        guard store(pin, account: Self.pinAccount) else { return .wrongLength }
        hasPIN = true
        mustCreatePIN = false
        if Self.present(Self.duressAccount, readSecret) == false { fillDuressSlot() }
        return nil
    }

    func setDuressPIN(_ pin: String) -> SetupProblem? {
        guard hasPIN else { return .needsPIN }
        if let problem = Self.check(pin) { return problem }
        if matches(pin, account: Self.pinAccount) { return .sameAsPIN }
        guard store(pin, account: Self.duressAccount) else { return .wrongLength }
        return nil
    }

    /// Removes the PIN and the duress PIN, only after a panic wipe. A new PIN is asked for the next time
    /// the app is left or launched.
    func removePINs() {
        for account in [Self.pinAccount, Self.duressAccount, Self.failureAccount, Self.biometricHashAccount] + Self.legacyAccounts.map(\.0) {
            try? vault.removeSecret(account: account)
        }
        biometrics.remove()
        biometricsOn = false
        biometricsInvalidated = false
        hasPIN = false
        isLocked = false
        mustCreatePIN = false
    }

    // MARK: Face ID

    enum BiometricSetup: Equatable {
        case on
        case wrongPIN
        case unavailable
        case failed

        var message: String {
            switch self {
            case .on: return "Face ID is on."
            case .wrongPIN: return "Wrong PIN."
            case .unavailable: return "Set up Face ID in the iPhone's Settings first."
            case .failed: return "Could not turn it on. Try again."
            }
        }
    }

    /// Turns Face ID unlock on. Needs the current PIN (the duress PIN does not count and does not wipe here).
    func turnOnBiometrics(pin: String) -> BiometricSetup {
        guard hasPIN, !unreadable else { return .failed }
        guard matches(pin, account: Self.pinAccount) else { return .wrongPIN }
        guard biometrics.kind != nil else { return .unavailable }
        var token = Data(count: 32)
        let status = token.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { return .failed }
        do {
            try biometrics.save(token)
            try vault.setSecret(Data(SHA256.hash(data: token)), account: Self.biometricHashAccount)
        } catch {
            turnOffBiometrics()
            return .failed
        }
        biometricsOn = true
        biometricsInvalidated = false
        return .on
    }

    func turnOffBiometrics() {
        biometrics.remove()
        try? vault.removeSecret(account: Self.biometricHashAccount)
        biometricsOn = false
    }

    /// Asks for Face ID on its own, once per lock, and returns at once. The Keychain read that shows the sheet
    /// starts now on a background thread rather than waiting its turn behind the rest of the main thread's
    /// work, so the sheet comes up as soon as DLChat is on screen.
    func askForBiometricsIfDue(reason: String = "Unlock DLChat") {
        guard !biometricAskedThisLock, let pending = startBiometricRead(reason: reason) else { return }
        Task { await finishBiometricRead(pending) }
    }

    /// Asks for Face ID and unlocks on a match. Anything else leaves the app locked with the PIN pad up;
    /// if the Face ID item is gone (faces changed), Face ID is turned off until the PIN turns it on again.
    @discardableResult
    func unlockWithBiometrics(reason: String = "Unlock DLChat") async -> Bool {
        guard let pending = startBiometricRead(reason: reason) else { return false }
        return await finishBiometricRead(pending)
    }

    private func startBiometricRead(reason: String) -> Task<BiometricRead, Never>? {
        // One sheet at a time: a tap on the Face ID button while it is already up does nothing.
        guard isLocked, biometricsOn, !unreadable, !biometricPromptOpen else { return nil }
        biometricAskedThisLock = true
        biometricPromptOpen = true
        LaunchTiming.mark("faceid.ask")
        let key = biometrics
        return Task.detached { await key.read(reason: reason) }
    }

    private func finishBiometricRead(_ pending: Task<BiometricRead, Never>) async -> Bool {
        let result = await pending.value
        LaunchTiming.mark("faceid.answer")
        biometricPromptOpen = false
        // The app may have been wiped or unlocked while the sheet was up.
        guard isLocked, biometricsOn else { return false }
        switch result {
        case .token(let token):
            guard let expected = (try? readSecret(Self.biometricHashAccount)) ?? nil,
                  Data(SHA256.hash(data: token)) == expected
            else {
                turnOffBiometrics()
                biometricsInvalidated = true
                return false
            }
            try? vault.removeSecret(account: Self.failureAccount)
            isLocked = false
            return true
        case .declined:
            return false
        case .invalidated:
            turnOffBiometrics()
            biometricsInvalidated = true
            return false
        }
    }

    static func check(_ pin: String) -> SetupProblem? {
        if !pin.allSatisfy({ $0.isASCII && $0.isNumber }) { return .notDigits }
        if !allowedLengths.contains(pin.count) { return .wrongLength }
        return nil
    }

    // MARK: Hashing

    private func store(_ pin: String, account: String) -> Bool {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        do {
            try vault.setSecret(salt + hash(pin, salt: salt), account: account)
            return true
        } catch {
            return false
        }
    }

    private func matches(_ pin: String, account: String) -> Bool {
        // Always hash, even with nothing stored, so the time taken does not say whether a duress PIN exists.
        let stored = (try? readSecret(account)) ?? nil
        let blob = stored.flatMap { $0.count == 48 ? $0 : nil } ?? Data(count: 48)
        let salt = blob.prefix(16)
        let expected = Data(blob.suffix(32))
        let actual = hash(pin, salt: Data(salt))
        var difference: UInt8 = stored == nil ? 1 : 0
        for (a, b) in zip(actual, expected) { difference |= a ^ b }
        return difference == 0
    }

    private func hash(_ pin: String, salt: Data) -> Data {
        let password = Array(pin.utf8)
        var out = Data(count: 32)
        let status = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                    outBytes.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return out
    }

    // MARK: Failure count

    private func loadFailures() -> Failures {
        guard let data = (try? readSecret(Self.failureAccount)) ?? nil else { return Failures() }
        return (try? JSONDecoder().decode(Failures.self, from: data)) ?? Failures()
    }

    private func saveFailures(_ failures: Failures) {
        if let data = try? JSONEncoder().encode(failures) { try? vault.setSecret(data, account: Self.failureAccount) }
    }
}
