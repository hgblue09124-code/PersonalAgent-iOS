import PAFoundation
import PAProviders

public enum LocalProviderBoundary {
    public static let providerID = ProviderID(rawValue: "local")
    public static let availableInMilestone = "M2"
    public static let liveNetworkVerified = false
    public static let defaultEndpoint = "http://127.0.0.1:11434/v1/chat/completions"
    public static let intendedCompatibleServers = [
        "ollama",
        "lmstudio",
        "llama.cpp",
        "vllm",
        "custom",
    ]

    public static let declaredIdentity = ProviderIdentity(
        id: providerID,
        displayName: "Local",
        models: [
            ModelIdentity(id: ModelID(rawValue: "local"), displayName: "Local", contextTokenLimit: 8192),
        ]
    )
}

/// Local transport boundary. No on-device model is bundled. Requires a user-supplied endpoint.
public struct LocalProvider: LLMProvider {
    private let inner: HTTPChatProvider

    public init(
        transport: any ProviderTransport,
        credentials: any CredentialResolving,
        configuration: ProviderConfiguration? = nil
    ) {
        let config = configuration ?? ProviderConfiguration(
            providerID: LocalProviderBoundary.providerID,
            endpointURL: LocalProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "local")
        )
        self.inner = HTTPChatProvider(
            identity: LocalProviderBoundary.declaredIdentity,
            configuration: config,
            transport: transport,
            credentials: credentials,
            capabilities: [.textGeneration, .streaming, .localInference],
            authorizationScheme: config.credential == nil ? .none : .bearer
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
