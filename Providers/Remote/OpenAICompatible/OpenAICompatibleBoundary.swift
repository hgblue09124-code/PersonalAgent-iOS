import PAKernel
import PAProviders
import PAProvidersRemote

public enum OpenAICompatibleProviderBoundary {
    public static let providerID = ProviderID(rawValue: "openai-compatible")
    public static let availableInMilestone = "M2"
    public static let liveNetworkVerified = false

    public static let declaredIdentity = ProviderIdentity(
        id: providerID,
        displayName: "OpenAI Compatible",
        models: [
            ModelIdentity(id: ModelID(rawValue: "compatible"), displayName: "Compatible", contextTokenLimit: 32_768),
        ]
    )
}

public struct OpenAICompatibleProvider: LLMProvider {
    private let inner: HTTPChatProvider

    public init(
        transport: any ProviderTransport,
        credentials: any CredentialResolving,
        configuration: ProviderConfiguration
    ) {
        let declared = OpenAICompatibleProviderBoundary.declaredIdentity
        let configuredModel = ModelIdentity(
            id: configuration.defaultModel,
            displayName: configuration.defaultModel.rawValue,
            contextTokenLimit: declared.models.first?.contextTokenLimit ?? 32_768
        )
        let identity = ProviderIdentity(
            id: declared.id,
            displayName: declared.displayName,
            models: [configuredModel]
        )
        self.inner = HTTPChatProvider(
            identity: identity,
            configuration: configuration,
            transport: transport,
            credentials: credentials,
            capabilities: [.textGeneration, .streaming],
            authorizationScheme: configuration.credential == nil ? .none : .bearer
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
