import Combine
import Foundation
import PAKernel
import PAProviders
import PAProvidersRemote
import PAProvidersGrok
import PAProvidersOpenAI
import PASecurity

@MainActor
final class ProviderConfigurationStore: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable {
        case openAI = "openai"
        case grok = "grok"
        var id: String { rawValue }
        var title: String { self == .openAI ? "OpenAI" : "Grok" }
        var account: String { "provider.\(rawValue).api-key" }
        var credentialProviderID: ProviderID { ProviderID(rawValue: rawValue) }
        var model: ModelID { self == .openAI ? ModelID(rawValue: "gpt-4o-mini") : ModelID(rawValue: "grok-3") }
        var endpoint: String { self == .openAI ? OpenAIProviderBoundary.defaultEndpoint : GrokProviderBoundary.defaultEndpoint }
    }

    @Published var selected: Provider? { didSet { UserDefaults.standard.set(selected?.rawValue, forKey: Self.providerKey) } }
    static let providerKey = "provider.active.id"
    init() { selected = UserDefaults.standard.string(forKey: Self.providerKey).flatMap(Provider.init(rawValue:)) }
}

@MainActor
enum AppProviderFactory {
    static func makeProvider(configuration: ProviderConfigurationStore) -> (any LLMProvider)? {
        guard let selected = configuration.selected else { return nil }
        let credentials = SecretStoreCredentials(store: KeychainSecretStore())
        let transport = SecurityNetworkTransport(network: URLSessionNetworkAccess())
        let ref = ProviderCredentialRef(providerID: selected.credentialProviderID, account: selected.account)
        let config = PAKernel.ProviderConfiguration(providerID: selected.credentialProviderID, endpointURL: selected.endpoint, defaultModel: selected.model, credential: ref, maxRetryAttempts: 1)
        switch selected {
        case .openAI: return OpenAIProvider(transport: transport, credentials: credentials, configuration: config)
        case .grok: return GrokProvider(transport: transport, credentials: credentials, configuration: config)
        }
    }

    static func testConnection(provider: ProviderConfigurationStore.Provider, apiKey: String) async throws -> String {
        let store = KeychainSecretStore()
        let ref = ProviderCredentialRef(providerID: provider.credentialProviderID, account: provider.account)
        try store.store(account: ref.account, secret: Data(apiKey.utf8))
        let credentials = SecretStoreCredentials(store: store)
        let transport = SecurityNetworkTransport(network: URLSessionNetworkAccess())
        let config = PAKernel.ProviderConfiguration(providerID: provider.credentialProviderID, endpointURL: provider.endpoint, defaultModel: provider.model, credential: ref, timeoutNanoseconds: 20_000_000_000)
        let llm: any LLMProvider = provider == .openAI
            ? OpenAIProvider(transport: transport, credentials: credentials, configuration: config)
            : GrokProvider(transport: transport, credentials: credentials, configuration: config)
        let response = try await llm.complete(LLMRequest(model: provider.model, prompt: "Reply with OK"))
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ProviderConnectionError.emptyResponse }
        return text
    }
}

enum ProviderConnectionError: LocalizedError {
    case emptyResponse
    var errorDescription: String? { "Provider returned an empty response." }
}
