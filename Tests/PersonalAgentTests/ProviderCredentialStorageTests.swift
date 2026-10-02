import Foundation
import Testing
import PASecurity

@Suite("Provider credential storage")
struct ProviderCredentialStorageTests {
    @Test func inMemorySecretStoreStoresLoadsAndDeletes() throws {
        let store = InMemorySecretStore()
        let secret = Data("test-secret".utf8)
        try store.store(account: "provider.openai.api-key", secret: secret)
        #expect(try store.load(account: "provider.openai.api-key") == secret)
        try store.delete(account: "provider.openai.api-key")
        #expect(try store.load(account: "provider.openai.api-key") == nil)
    }
}
