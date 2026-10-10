import Foundation
import PAKernel
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
        let sanitizedText = LocalModelOutputValidator.sanitize(text: response.text)
        try LocalModelOutputValidator.validate(text: sanitizedText)
        return LLMResponse(
            text: sanitizedText,
            finishReason: response.finishReason,
            model: request.model
        )
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let genRequest = mapRequest(request)
        let engineStream = engine.generateStream(request: genRequest)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulated = ""
                    for try await chunk in engineStream {
                        try Task.checkCancellation()
                        accumulated += chunk.textDelta
                    }
                    let sanitizedText = LocalModelOutputValidator.sanitize(text: accumulated)
                    try LocalModelOutputValidator.validate(text: sanitizedText)
                    // Do not leak repeated/raw tokens before the final quality gate.
                    // Emit the verified local result only after sanitization.
                    continuation.yield(.delta(sanitizedText))
                    let finalResponse = LLMResponse(
                        text: sanitizedText,
                        finishReason: "stop",
                        model: request.model
                    )
                    continuation.yield(.completed(finalResponse))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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
