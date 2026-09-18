import Foundation
import PAFoundation

/// Secrets live in Keychain (or a test double). Never SwiftData / UserDefaults.
public protocol SecretStore: Sendable {
    func store(account: String, secret: Data) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
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
