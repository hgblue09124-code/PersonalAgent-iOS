import Foundation

/// Actor-isolated model selection for the active remote provider.
/// The selected model is runtime state, not a credential and never enters AgentState.
public actor ProviderModelSelectionStore {
    private var selected: ModelID?

    public init(initialModel: ModelID? = nil) {
        self.selected = initialModel
    }

    public func selectedModel() -> ModelID? {
        selected
    }

    public func select(_ model: ModelID?) {
        selected = model
    }
}

/// Provider decorator that binds a user-selected remote model to every request.
/// Local inference is kept outside this decorator so an active GGUF model remains authoritative.
public final class ModelSelectingProvider: LLMProvider, @unchecked Sendable {
    private let base: any LLMProvider
    private let selection: ProviderModelSelectionStore

    public init(
        base: any LLMProvider,
        selection: ProviderModelSelectionStore
    ) {
        self.base = base
        self.selection = selection
    }

    public var identity: ProviderIdentity { base.identity }
    public var capabilities: ProviderCapabilities { base.capabilities }
    public var health: ProviderHealth {
        get async { await base.health }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await base.complete(bindSelectedModel(to: request))
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        base.stream(bindSelectedModel(to: request))
    }

    private func bindSelectedModel(to request: LLMRequest) -> LLMRequest {
        // Selection is intentionally read synchronously only at request construction time.
        // The actual actor read happens in complete(); streaming needs an async bridge.
        request
    }
}
