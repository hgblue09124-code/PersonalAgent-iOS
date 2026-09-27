import Foundation
import PAProviders
import PASecurity

import Foundation
import PAKernel
import PASecurity

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
