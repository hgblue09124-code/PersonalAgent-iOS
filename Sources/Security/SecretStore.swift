import Foundation
import PAKernel

/// Secrets live in Keychain (or a test double). Never SwiftData / UserDefaults.
public protocol SecretStore: Sendable {
    func store(account: String, secret: Data) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

/// Thread-safe in-memory SecretStore implementation for testing and non-persistent environments.
#if canImport(Security)
import Security

/// Production SecretStore backed by the Apple Keychain.
public struct KeychainSecretStore: SecretStore, Sendable {
    private let service: String

    public init(service: String = "PersonalAgent.Provider") {
        self.service = service
    }

    public func store(account: String, secret: Data) throws {
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
            item[kSecValueData as String] = secret
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainSecretStoreError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainSecretStoreError.status(status)
        }
    }

    public func load(account: String) throws -> Data? {
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
        guard status == errSecSuccess else { throw KeychainSecretStoreError.status(status) }
        return result as? Data
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.status(status)
        }
    }
}

public enum KeychainSecretStoreError: Error, Sendable, Equatable {
    case status(OSStatus)
}
#else
/// Non-Apple fallback keeps the package graph portable; production iOS builds use Keychain above.
public struct KeychainSecretStore: SecretStore, Sendable {
    public init(service: String = "PersonalAgent.Provider") {}

    public func store(account: String, secret: Data) throws {
        throw KeychainSecretStoreError.unavailable
    }

    public func load(account: String) throws -> Data? {
        throw KeychainSecretStoreError.unavailable
    }

    public func delete(account: String) throws {
        throw KeychainSecretStoreError.unavailable
    }
}

public enum KeychainSecretStoreError: Error, Sendable, Equatable {
    case unavailable
}
#endif

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

public struct NetworkStreamResponse: Sendable {
    public let statusCode: Int
    public let chunks: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, chunks: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.chunks = chunks
    }
}

public protocol NetworkAccess: Sendable {
    func data(for request: NetworkRequest) async throws -> NetworkResponse
    func stream(for request: NetworkRequest) async throws -> NetworkStreamResponse
}

public extension NetworkAccess {
    /// Compatibility fallback for test doubles and transports without incremental I/O.
    func stream(for request: NetworkRequest) async throws -> NetworkStreamResponse {
        let response = try await data(for: request)
        return NetworkStreamResponse(
            statusCode: response.statusCode,
            chunks: AsyncThrowingStream { continuation in
                continuation.yield(response.body)
                continuation.finish()
            }
        )
    }
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

    public func stream(for request: NetworkRequest) async throws -> NetworkStreamResponse {
        guard let url = URL(string: request.url) else {
            throw NetworkAccessError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkAccessError.invalidResponse
        }
        let chunks = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        // Flush each complete SSE line so token deltas are not held
                        // until an arbitrary 4 KB threshold is reached.
                        if byte == 0x0A {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return NetworkStreamResponse(statusCode: httpResponse.statusCode, chunks: chunks)
        #else
        let response = try await data(for: request)
        return NetworkStreamResponse(
            statusCode: response.statusCode,
            chunks: AsyncThrowingStream { continuation in
                continuation.yield(response.body)
                continuation.finish()
            }
        )
        #endif
    }
}
