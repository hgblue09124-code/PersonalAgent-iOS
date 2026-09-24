import Foundation
import PAFoundation

#if canImport(Security)
import Security
#endif

/// Secrets live in Keychain (or a test double). Never SwiftData / UserDefaults.
public protocol SecretStore: Sendable {
    func store(account: String, secret: Data) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

/// Production Keychain-backed SecretStore.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.personalagent.ios.provider-credentials") {
        self.service = service
    }

    public func store(account: String, secret: Data) throws {
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            for (key, value) in attributes { item[key] = value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretStoreError.keychainStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychainStatus(status)
        }
#else
        throw SecretStoreError.unavailable
#endif
    }

    public func load(account: String) throws -> Data? {
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychainStatus(status)
        }
        return result as? Data
#else
        throw SecretStoreError.unavailable
#endif
    }

    public func delete(account: String) throws {
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychainStatus(status)
        }
#else
        throw SecretStoreError.unavailable
#endif
    }
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case unavailable
    case keychainStatus(OSStatus)
}

/// Thread-safe in-memory SecretStore implementation for testing and non-persistent environments.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var secrets: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func store(account: String, secret: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        secrets[account] = secret
    }

    public func load(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[account]
    }

    public func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        secrets.removeValue(forKey: account)
    }
}

/// Provider credentials stay outside AgentState.
public struct ProviderCredentialRef: Hashable, Sendable, Codable {
    public let providerID: ProviderID
    public let account: String

    public init(providerID: ProviderID, account: String) {
        self.providerID = providerID
        self.account = account
    }
}

public struct NetworkRequest: Sendable, Equatable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct NetworkResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol NetworkAccess: Sendable {
    func data(for request: NetworkRequest) async throws -> NetworkResponse
}

public enum NetworkAccessError: Error, Sendable, Equatable {
    case invalidURL
    case invalidResponse
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Production NetworkAccess implementation backed by URLSession.
public struct URLSessionNetworkAccess: NetworkAccess, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: NetworkRequest) async throws -> NetworkResponse {
        guard let url = URL(string: request.url) else {
            throw NetworkAccessError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkAccessError.invalidResponse
        }
        return NetworkResponse(statusCode: httpResponse.statusCode, body: data)
    }
}
