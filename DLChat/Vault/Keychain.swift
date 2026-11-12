import Foundation
import Security

enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

/// Generic-password items for one service. Every item is `WhenUnlockedThisDeviceOnly`,
/// so none of it leaves the phone in a backup or syncs through iCloud.
struct Keychain {
    let service: String

    private func query(_ account: String? = nil) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    func set(_ data: Data, account: String) throws {
        var attrs = query(account)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = false
        attrs[kSecValueData as String] = data
        var status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(
                query(account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func get(account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }

    func accounts() throws -> [String] {
        var q = query()
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        let rows = out as? [[String: Any]] ?? []
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func accessibility(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return (out as? [String: Any])?[kSecAttrAccessible as String] as? String
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    func deleteAll() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
