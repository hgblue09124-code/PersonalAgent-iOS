import Foundation
import PAFoundation
import PAProviders

/// Adapter bridging any on-device `LocalModelEngine` (MLX, llama.cpp, Core ML, etc.) into the `LLMProvider` contract.
/// External model engines enter through this adapter without modifying `Kernel` or exposing vendor details.
public final class LocalModelProviderAdapter: LLMProvider, @unchecked Sendable {
    private let engine: any LocalModelEngine
    private let providerIdentity: ProviderIdentity

    public init(engine: any LocalModelEngine) {
        self.engine = engine
        let modelIdentity = ModelIdentity(
            id: engine.identity.id,
            displayName: engine.identity.name,
            contextTokenLimit: engine.identity.contextTokenLimit
        )
        self.providerIdentity = ProviderIdentity(
            id: ProviderID(rawValue: "local-\(engine.identity.id.rawValue)"),
            displayName: "Local Engine (\(engine.identity.name))",
            models: [modelIdentity]
        )
    }

    public var identity: ProviderIdentity { providerIdentity }

    public var capabilities: ProviderCapabilities {
        [.textGeneration, .streaming, .localInference]
    }

    public var health: ProviderHealth {
        get async {
            let availability = await engine.availability
            switch availability {
            case .ready:
                return .healthy
            case .notDownloaded, .downloading, .unsupported:
                return .degraded
            case .error:
                return .unavailable
            }
        }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let genRequest = mapRequest(request)
        let response = try await engine.generate(request: genRequest)
        return LLMResponse(
            text: response.text,
            finishReason: response.finishReason,
            model: request.model
        )
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let genRequest = mapRequest(request)
        let engineStream = engine.generateStream(request: genRequest)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var accumulated = ""
                    for try await chunk in engineStream {
                        accumulated += chunk.textDelta
                        continuation.yield(.delta(chunk.textDelta))
                    }
                    try LocalModelOutputValidator.validate(text: accumulated)
                    let finalResponse = LLMResponse(
                        text: accumulated,
                        finishReason: "stop",
                        model: request.model
                    )
                    continuation.yield(.completed(finalResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func mapRequest(_ request: LLMRequest) -> LocalModelGenerationRequest {
        let systemPrompt = request.messages.first(where: { $0.role == .system })?.content
        let prompt = request.prompt
        return LocalModelGenerationRequest(
            prompt: prompt,
            systemPrompt: systemPrompt,
            maxTokens: request.parameters.maxOutputTokens,
            temperature: request.parameters.temperature
        )
    }
}
