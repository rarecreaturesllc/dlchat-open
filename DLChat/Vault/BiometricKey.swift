import Foundation
import LocalAuthentication
import Security

/// What a Face ID (or Touch ID) read of the unlock token ended in.
enum BiometricRead: Equatable {
    case token(Data)
    /// Cancelled, failed, "Use PIN" tapped, or Face ID locked out by iOS. The PIN pad stays.
    case declined
    /// The item is gone: iOS drops it when a face or finger is added or removed, or the phone passcode
    /// is turned off. Face ID has to be turned on again with the PIN.
    case invalidated
}

/// Keeps one random token in a Keychain item that iOS releases only after a Face ID / Touch ID match
/// with the faces or fingers enrolled when it was saved (`biometryCurrentSet`). There is deliberately no
/// iPhone-passcode fallback: the way in without a face is DLChat's own PIN.
protocol BiometricKey {
    /// "Face ID" or "Touch ID" when this phone has it enrolled, otherwise nil.
    var kind: String? { get }
    func save(_ token: Data) throws
    func read(reason: String) async -> BiometricRead
    func remove()
}

struct KeychainBiometricKey: BiometricKey {
    /// Same service as the vault, so the panic wipe's delete-all removes this item too.
    let service: String
    static let account = "lock.5"

    var kind: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: Self.account]
    }

    func save(_ token: Data) throws {
        remove()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error)
        else { throw KeychainError.status(errSecParam) }
        var attrs = query
        attrs[kSecAttrAccessControl as String] = access
        attrs[kSecAttrSynchronizable as String] = false
        attrs[kSecValueData as String] = token
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func read(reason: String) async -> BiometricRead {
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"
        context.localizedCancelTitle = "Use PIN"
        context.localizedReason = reason
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = context
        let request = q
        // SecItemCopyMatching waits for the Face ID sheet, so it must not run on the main thread.
        return await Task.detached {
            var out: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &out)
            switch status {
            case errSecSuccess: return (out as? Data).map(BiometricRead.token) ?? .invalidated
            case errSecItemNotFound: return .invalidated
            default: return .declined
            }
        }.value
    }

    func remove() {
        SecItemDelete(query as CFDictionary)
    }
}
