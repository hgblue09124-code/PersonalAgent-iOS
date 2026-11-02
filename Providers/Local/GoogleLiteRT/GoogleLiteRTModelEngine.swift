import Foundation
import LiteRTLM
import PAKernel
import PAProviders

/// LocalModelEngine backed by Google's official LiteRT-LM Swift runtime.
/// Model files must use Google's .litertlm format.
public actor GoogleLiteRTModelEngine: LocalModelEngine {
    public let identity: LocalModelIdentity
    private var engine: Engine?
    private var state: LocalModelLifecycleState = .unloaded

    public init(identity: LocalModelIdentity) {
        self.identity = identity
    }

    public var availability: LocalModelAvailability {
        get async {
            guard let url = identity.localURL else { return .notDownloaded }
            return FileManager.default.fileExists(atPath: url.path) ? .ready : .notDownloaded
        }
    }

    public var lifecycleState: LocalModelLifecycleState {
        get async { state }
    }

    public func load(options: LocalModelLoadingOptions) async throws {
        if case .loaded = state { return }
        guard let url = identity.localURL,
              FileManager.default.fileExists(atPath: url.path) else {
            state = .failed(reason: "LiteRT-LM model file is missing")
            throw GoogleLiteRTError.modelFileMissing
        }

        state = .loading(progress: 0.1)
        do {
            let config = try EngineConfig(
                modelPath: url.path,
                backend: .gpu,
                maxNumTokens: options.maxTokens
            )
            let runtime = Engine(engineConfig: config)
            try await runtime.initialize()
            engine = runtime
            state = .loaded
        } catch {
            state = .failed(reason: error.localizedDescription)
            throw error
        }
    }

    public func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
        var output = ""
        for try await chunk in generateStream(request: request) {
            output += chunk.textDelta
        }
        return LocalModelResponse(text: output, finishReason: "stop")
    }

    public func generateStream(
        request: LocalModelGenerationRequest
    ) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
        let runtime = engine
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let runtime else { throw GoogleLiteRTError.modelNotLoaded }
                    let systemMessage = request.systemPrompt.map {
                        Message($0, role: .system)
                    }
                    let config = ConversationConfig(systemMessage: systemMessage)
                    let conversation = try await runtime.createConversation(with: config)
                    for try await message in conversation.sendMessageStream(
                        Message(request.prompt),
                        maxOutputTokens: request.maxTokens
                    ) {
                        try Task.checkCancellation()
                        let text = message.toString
                        if !text.isEmpty {
                            continuation.yield(LocalModelStreamChunk(textDelta: text))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func cancel() async {}

    public func unload() async throws {
        engine = nil
        state = .unloaded
    }
}

public enum GoogleLiteRTError: Error, LocalizedError {
    case modelFileMissing
    case modelNotLoaded

    public var errorDescription: String? {
        switch self {
        case .modelFileMissing: return "Không tìm thấy model .litertlm"
        case .modelNotLoaded: return "Google LiteRT-LM chưa được nạp model"
        }
    }
}
