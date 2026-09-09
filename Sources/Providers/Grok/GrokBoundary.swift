import PAFoundation
import PAProviders

public enum GrokProviderBoundary {
    public static let providerID = ProviderID(rawValue: "grok")
    public static let availableInMilestone = "M2"
    public static let liveNetworkVerified = false
    public static let defaultEndpoint = "https://api.x.ai/v1/chat/completions"

    public static let declaredIdentity = ProviderIdentity(
        id: providerID,
        displayName: "Grok",
        models: [
            ModelIdentity(id: ModelID(rawValue: "grok-3"), displayName: "Grok 3", contextTokenLimit: 131_072),
        ]
    )
}

/// Adapter boundary for xAI Grok. Live network calls require injected transport + credentials.
public struct GrokProvider: LLMProvider {
    private let inner: HTTPChatProvider

    public init(
        transport: any ProviderTransport,
        credentials: any CredentialResolving,
        configuration: ProviderConfiguration? = nil
    ) {
        let config = configuration ?? ProviderConfiguration(
            providerID: GrokProviderBoundary.providerID,
            endpointURL: GrokProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "grok-3")
        )
        self.inner = HTTPChatProvider(
            identity: GrokProviderBoundary.declaredIdentity,
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
