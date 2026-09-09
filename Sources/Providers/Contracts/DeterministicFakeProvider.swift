import Foundation
import PAFoundation

/// Test and composition double. Not a live model. Behavior is scripted and deterministic.
public struct DeterministicFakeProvider: LLMProvider {
    public enum Script: Sendable, Equatable {
        case success(LLMResponse)
        case failure(ProviderRuntimeError)
        case unsupported(ProviderCapabilities)
        case hangUntilCancelled
        case timeout
    }

    public let identity: ProviderIdentity
    public let capabilities: ProviderCapabilities
    private let script: Script

    public init(
        identity: ProviderIdentity = ProviderIdentity(
            id: ProviderID(rawValue: "fake"),
            displayName: "Deterministic Fake",
            models: [ModelIdentity(id: ModelID(rawValue: "fake-text"), displayName: "Fake Text", contextTokenLimit: 8192)]
        ),
        capabilities: ProviderCapabilities = [.textGeneration, .streaming],
        script: Script = .success(LLMResponse(text: "ok", finishReason: "stop", model: ModelID(rawValue: "fake-text")))
    ) {
        self.identity = identity
        self.capabilities = capabilities
        self.script = script
    }

    public var health: ProviderHealth {
        get async {
            switch script {
            case .failure(.unavailable): return .unavailable
            case .timeout: return .degraded
            default: return .healthy
            }
        }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try Task.checkCancellation()
        switch script {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case .unsupported(let capability):
            throw ProviderRuntimeError.unsupportedCapability(String(capability.rawValue))
        case .hangUntilCancelled:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw ProviderRuntimeError.cancelled
        case .timeout:
            throw ProviderRuntimeError.timeout
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request)
                    if !response.text.isEmpty {
                        continuation.yield(.delta(response.text))
                    }
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderRuntimeError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
