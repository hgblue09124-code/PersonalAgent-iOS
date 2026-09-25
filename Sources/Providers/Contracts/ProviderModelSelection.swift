import Foundation
import PAFoundation

/// Actor-isolated model selection for the active remote provider.
/// The selected model is runtime state, not a credential and never enters AgentState.
public actor ProviderModelSelectionStore {
    private var selected: ModelID?
    private let defaults: UserDefaults?
    private let persistenceKey: String

    public init(
        initialModel: ModelID? = nil,
        defaults: UserDefaults? = .standard,
        persistenceKey: String = "personalagent.provider.selected-model"
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let raw = defaults?.string(forKey: persistenceKey), !raw.isEmpty {
            self.selected = ModelID(rawValue: raw)
        } else {
            self.selected = initialModel
        }
    }

    public func selectedModel() -> ModelID? {
        selected
    }

    public func select(_ model: ModelID?) {
        selected = model
        if let model {
            defaults?.set(model.rawValue, forKey: persistenceKey)
        } else {
            defaults?.removeObject(forKey: persistenceKey)
        }
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
        try await base.complete(await Self.bindSelectedModel(to: request, selection: selection))
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let base = self.base
        let selection = self.selection
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let boundRequest = await Self.bindSelectedModel(to: request, selection: selection)
                    for try await event in base.stream(boundRequest) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func bindSelectedModel(
        to request: LLMRequest,
        selection: ProviderModelSelectionStore
    ) async -> LLMRequest {
        guard let selected = await selection.selectedModel() else { return request }
        return LLMRequest(
            model: selected,
            messages: request.messages,
            parameters: request.parameters,
            toolsAllowed: request.toolsAllowed,
            metadata: request.metadata,
            timeoutNanoseconds: request.timeoutNanoseconds
        )
    }
}
