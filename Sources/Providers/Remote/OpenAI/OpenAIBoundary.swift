import PAFoundation
import PAProviders

public enum OpenAIProviderBoundary {
    public static let providerID = ProviderID(rawValue: "openai")
    public static let availableInMilestone = "M2"
    public static let liveNetworkVerified = false
    public static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"

    public static let declaredIdentity = ProviderIdentity(
        id: providerID,
        displayName: "OpenAI",
        models: [
            ModelIdentity(id: ModelID(rawValue: "gpt-4o-mini"), displayName: "GPT-4o mini", contextTokenLimit: 128_000),
        ]
    )
}

public struct OpenAIProvider: LLMProvider {
    private let inner: HTTPChatProvider

    public init(
        transport: any ProviderTransport,
        credentials: any CredentialResolving,
        configuration: ProviderConfiguration? = nil
    ) {
        let config = configuration ?? ProviderConfiguration(
            providerID: OpenAIProviderBoundary.providerID,
            endpointURL: OpenAIProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "gpt-4o-mini")
        )
        self.inner = HTTPChatProvider(
            identity: OpenAIProviderBoundary.declaredIdentity,
            configuration: config,
            transport: transport,
            credentials: credentials,
            capabilities: [.textGeneration, .streaming],
            authorizationScheme: .bearer
        )
    }

    public var identity: ProviderIdentity { inner.identity }
    public var capabilities: ProviderCapabilities { inner.capabilities }
    public var health: ProviderHealth { get async { await inner.health } }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await inner.complete(request)
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        inner.stream(request)
    }
}
