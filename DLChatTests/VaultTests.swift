import CryptoKit
import XCTest
@testable import DLChat

final class VaultTests: XCTestCase {
    private var directory: URL!
    private var service: String!
    private var vault: Vault!

    override func setUpWithError() throws {
        service = "app.dlchat.tests.\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appending(path: "vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        vault = Vault(service: service, directory: directory)
    }

    override func tearDownWithError() throws {
        try? vault.wipe()
        try? FileManager.default.removeItem(at: directory)
    }

    func testSecretRoundTrip() throws {
        let value = Data("synthetic-secret".utf8)
        try vault.setSecret(value, account: "g1")
        XCTAssertEqual(try vault.secret(account: "g1"), value)
        try vault.setSecret(Data("changed".utf8), account: "g1")
        XCTAssertEqual(try vault.secret(account: "g1"), Data("changed".utf8))
        try vault.removeSecret(account: "g1")
        XCTAssertNil(try vault.secret(account: "g1"))
    }

    func testKeychainItemsAreThisDeviceOnly() throws {
        try vault.setSecret(Data([1, 2, 3]), account: "g1")
        try vault.writeStore(Data("x".utf8))
        let keychain = Keychain(service: service)
        for account in ["g1", Vault.storeKeyAccount] {
            XCTAssertEqual(
                try keychain.accessibility(account: account),
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String, account)
        }
    }

    func testStoreRoundTripAndEmpty() throws {
        XCTAssertNil(try vault.readStore())
        let plain = Data("synthetic store contents".utf8)
        try vault.writeStore(plain)
        XCTAssertEqual(try vault.readStore(), plain)
        let second = Data("second write".utf8)
        try vault.writeStore(second)
        XCTAssertEqual(try vault.readStore(), second)
    }

    func testStoreFileIsSealedAndExcludedFromBackup() throws {
        let marker = "MARKER-plaintext-should-not-appear"
        try vault.writeStore(Data(marker.utf8))
        let onDisk = try Data(contentsOf: vault.storeURL)
        XCTAssertNil(onDisk.range(of: Data(marker.utf8)))
        let file = try vault.storeURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(file.isExcludedFromBackup, true)
        let dir = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(dir.isExcludedFromBackup, true)
    }

    func testTamperedStoreIsRejected() throws {
        try vault.writeStore(Data("synthetic".utf8))
        var blob = try Data(contentsOf: vault.storeURL)
        blob[blob.count / 2] ^= 0x01
        try blob.write(to: vault.storeURL)
        XCTAssertThrowsError(try vault.readStore()) { XCTAssertEqual($0 as? VaultError, .corruptStore) }
    }

    func testWipeLeavesNoReadableData() throws {
        let marker = "MARKER-wipe-test-plaintext"
        try vault.setSecret(Data("phrase-marker".utf8), account: "g1")
        try vault.setSecret(Data("pin-marker".utf8), account: "lock")
        try vault.writeStore(Data(marker.utf8))
        let copy = try Data(contentsOf: vault.storeURL)
        let keyData = try XCTUnwrap(Keychain(service: service).get(account: Vault.storeKeyAccount))

        try vault.wipe()

        // Keychain: nothing left under the service.
        XCTAssertEqual(try Keychain(service: service).accounts(), [])
        XCTAssertNil(try vault.secret(account: "g1"))
        // Files: directory gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(try vault.readStore())
        // Crypto-erase: a copied ciphertext is useless with a fresh key, and the old key is not stored anywhere.
        let box = try ChaChaPoly.SealedBox(combined: copy)
        try vault.writeStore(Data("new".utf8))
        let newKey = try XCTUnwrap(Keychain(service: service).get(account: Vault.storeKeyAccount))
        XCTAssertNotEqual(newKey, keyData)
        XCTAssertThrowsError(try ChaChaPoly.open(box, using: SymmetricKey(data: newKey)))
    }

    func testReinstallDropsLeftoverSecretsButUpdateKeepsThem() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "vault-tests-\(UUID().uuidString)"))
        // Fresh install after a delete: no marker, no store file, old Keychain items still there.
        try vault.setSecret(Data("old group key".utf8), account: "group.old")
        vault.dropSecretsLeftFromEarlierInstall(defaults: defaults)
        XCTAssertNil(try vault.secret(account: "group.old"))

        // Later launches leave new secrets alone.
        try vault.setSecret(Data("new".utf8), account: "group.new")
        vault.dropSecretsLeftFromEarlierInstall(defaults: defaults)
        XCTAssertEqual(try vault.secret(account: "group.new"), Data("new".utf8))

        // An update from a build without the marker: the store file is there, so nothing is dropped.
        let updated = try XCTUnwrap(UserDefaults(suiteName: "vault-tests-\(UUID().uuidString)"))
        try vault.writeStore(Data("groups".utf8))
        vault.dropSecretsLeftFromEarlierInstall(defaults: updated)
        XCTAssertEqual(try vault.secret(account: "group.new"), Data("new".utf8))
        XCTAssertEqual(try vault.readStore(), Data("groups".utf8))
    }

    func testWipeTwiceIsHarmless() throws {
        try vault.wipe()
        try vault.wipe()
    }
}
