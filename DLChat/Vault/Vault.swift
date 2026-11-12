import CryptoKit
import Foundation

enum VaultError: Error, Equatable {
    case corruptStore
    case keyMissing
}

/// Keychain secrets plus one sealed store file. The store key lives only in the Keychain,
/// so deleting it first makes every copy of the file unreadable (crypto-erase).
final class Vault {
    static let storeKeyAccount = "storeKey"

    private let keychain: Keychain
    private let directory: URL
    private let fileName = "store.bin"

    /// `service` and `directory` are injectable so tests never touch real data.
    init(service: String = "app.dlchat.vault", directory: URL? = nil) {
        self.keychain = Keychain(service: service)
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Vault", directoryHint: .isDirectory)
    }

    /// The Keychain service every secret of this vault lives under.
    var service: String { keychain.service }

    var storeURL: URL { storeURL(named: fileName) }

    /// Another sealed file beside the store, under the same store key, so Wipe's crypto-erase covers it too.
    func storeURL(named name: String) -> URL { directory.appending(path: name, directoryHint: .notDirectory) }

    // MARK: Secrets

    func setSecret(_ data: Data, account: String) throws {
        precondition(account != Self.storeKeyAccount, "reserved account")
        try keychain.set(data, account: account)
    }

    func secret(account: String) throws -> Data? {
        try keychain.get(account: account)
    }

    func removeSecret(account: String) throws {
        precondition(account != Self.storeKeyAccount, "reserved account")
        try keychain.delete(account: account)
    }

    // MARK: Sealed store

    /// What a sealed file is on disk right now: nil when there is none. Every write replaces the file
    /// atomically (a new file number), so any write, by this Vault or another, changes the stamp.
    struct FileStamp: Equatable {
        let number: Int
        let modified: Date?
        let size: Int
    }

    func stamp(named name: String? = nil) -> FileStamp? {
        let url = storeURL(named: name ?? fileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.systemFileNumber] as? Int else { return nil }
        return FileStamp(number: number, modified: attributes[.modificationDate] as? Date,
                         size: (attributes[.size] as? Int) ?? -1)
    }

    /// Counts wipes started. Anything decrypted from the store and kept in memory is dropped when this changes.
    private(set) var wipesStarted = 0

    /// Returns nil when no store has been written yet.
    func readStore(named name: String? = nil) throws -> Data? {
        let url = storeURL(named: name ?? fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let keyData = try keychain.get(account: Self.storeKeyAccount) else { throw VaultError.keyMissing }
        let blob = try Data(contentsOf: url)
        do {
            let box = try ChaChaPoly.SealedBox(combined: blob)
            return try ChaChaPoly.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw VaultError.corruptStore
        }
    }

    func writeStore(_ plaintext: Data, named name: String? = nil) throws {
        let url = storeURL(named: name ?? fileName)
        let key = try storeKey()
        let sealed = try ChaChaPoly.seal(plaintext, using: key).combined
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
        var file = url
        try file.setResourceValues(values)
    }

    func removeStore(named name: String) {
        try? FileManager.default.removeItem(at: storeURL(named: name))
    }

    private func storeKey() throws -> SymmetricKey {
        if let existing = try keychain.get(account: Self.storeKeyAccount) {
            return SymmetricKey(data: existing)
        }
        let fresh = SymmetricKey(size: .bits256)
        try keychain.set(fresh.withUnsafeBytes { Data($0) }, account: Self.storeKeyAccount)
        return fresh
    }

    // MARK: Reinstall

    /// Keychain items outlive the app: after a delete and reinstall they would still hold the old
    /// group keys and PIN hashes. UserDefaults and the store file are deleted with the app, so when
    /// neither is there this is a fresh install and the leftover Keychain items are dropped.
    /// An update keeps everything: its store file is still there, and the marker is set from then on.
    func dropSecretsLeftFromEarlierInstall(defaults: UserDefaults = .standard) {
        let marker = "vault.installed." + keychain.service
        guard !defaults.bool(forKey: marker) else { return }
        if !FileManager.default.fileExists(atPath: storeURL.path) { try? keychain.deleteAll() }
        defaults.set(true, forKey: marker)
    }

    // MARK: Wipe

    /// Deletes every Keychain item (the store key first), then the store directory.
    /// Both steps are attempted even if the first fails; the first error is rethrown.
    func wipe() throws {
        wipesStarted += 1
        var firstError: Error?
        do { try keychain.delete(account: Self.storeKeyAccount) } catch { firstError = error }
        do { try keychain.deleteAll() } catch { firstError = firstError ?? error }
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
    }
}
