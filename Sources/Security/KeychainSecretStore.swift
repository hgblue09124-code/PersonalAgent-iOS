import Foundation

#if canImport(Security)
import Security
#endif

/// Production SecretStore backed by the Apple Keychain.
/// No plaintext secret is persisted in UserDefaults, files, logs, or source.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.hgblue.PersonalAgent.provider-credentials") {
        self.service = service
    }

    public func store(account: String, secret: Data) throws {
        #if canImport(Security)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainSecretStoreError.status(Int32(addStatus)) }
            return
        }
        guard status == errSecSuccess else { throw KeychainSecretStoreError.status(Int32(status)) }
        #else
        throw KeychainSecretStoreError.unavailable
        #endif
    }

    public func load(account: String) throws -> Data? {
        #if canImport(Security)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainSecretStoreError.status(Int32(status)) }
        return result as? Data
        #else
        throw KeychainSecretStoreError.unavailable
        #endif
    }

    public func delete(account: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.status(Int32(status))
        }
        #else
        throw KeychainSecretStoreError.unavailable
        #endif
    }

    #if canImport(Security)
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    #endif
}

public enum KeychainSecretStoreError: Error, Sendable, Equatable {
    case unavailable
    case status(Int32)
}
