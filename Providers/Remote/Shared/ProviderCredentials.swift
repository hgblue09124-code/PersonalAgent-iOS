import Foundation
import PAKernel
import PASecurity

/// Credential refs may be held by composition, not by AgentState.
public struct ProviderBinding: Sendable, Equatable {
    public let providerID: ProviderID
    public let credential: ProviderCredentialRef?

    public init(providerID: ProviderID, credential: ProviderCredentialRef?) {
        self.providerID = providerID
        self.credential = credential
    }
}

public protocol CredentialResolving: Sendable {
    func secretData(for ref: ProviderCredentialRef) async throws -> Data?
}

public struct SecretStoreCredentials: CredentialResolving {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    public func secretData(for ref: ProviderCredentialRef) async throws -> Data? {
        try store.load(account: ref.account)
    }
}

public actor InMemoryCredentialVault: CredentialResolving {
    private var storage: [String: Data] = [:]

    public init() {}

    public func store(_ data: Data, for ref: ProviderCredentialRef) {
        storage[ref.account] = data
    }

    public func delete(_ ref: ProviderCredentialRef) {
        storage[ref.account] = nil
    }

    public func secretData(for ref: ProviderCredentialRef) async throws -> Data? {
        storage[ref.account]
    }
}
