import Foundation
import PAFoundation
import PAObservability
import PAEvents

/// Owns provider lifecycle and execution. Isolated from AgentRuntime.
public actor ProviderRuntime {
    public private(set) var lifecycle: ProviderLifecycle
    public private(set) var configuration: ProviderConfiguration?

    private var provider: any LLMProvider
    private let eventLog: (any EventLog)?
    private let logger: any AgentLogger
    private let sessionTrace: TraceID

    public init(
        provider: any LLMProvider,
        eventLog: (any EventLog)? = nil,
        logger: any AgentLogger = ProviderNullLogger(),
        sessionTrace: TraceID = TraceID()
    ) {
        self.provider = provider
        self.eventLog = eventLog
        self.logger = logger
        self.sessionTrace = sessionTrace
        self.lifecycle = .unconfigured
        self.configuration = nil
    }

    public var identity: ProviderIdentity { provider.identity }

    public var capabilities: ProviderCapabilities { provider.capabilities }

    public func configure(_ configuration: ProviderConfiguration) throws {
        guard configuration.providerID == provider.identity.id else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        guard lifecycle == .unconfigured || lifecycle == .configured || lifecycle == .failed else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        self.configuration = configuration
        lifecycle = .configured
        emit(kind: .providerConfigured, payload: [
            "providerID": configuration.providerID.rawValue,
            "hasCredentialRef": configuration.credential == nil ? "false" : "true",
        ])
    }

    public func ready() throws {
        guard lifecycle == .configured else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        lifecycle = .ready
        emit(kind: .providerReady, payload: ["providerID": provider.identity.id.rawValue])
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try prepareExecution()
        emit(kind: .providerInvoked, payload: [
            "providerID": provider.identity.id.rawValue,
            "model": request.model.rawValue,
            "mode": "complete",
        ])
        let timeout = request.timeoutNanoseconds ?? configuration?.timeoutNanoseconds
        let boundProvider = provider
        do {
            let response = try await execute(timeoutNanoseconds: timeout) {
                try await boundProvider.complete(request)
            }
            lifecycle = .completed
            emit(kind: .providerCompleted, payload: [
                "providerID": boundProvider.identity.id.rawValue,
                "finishReason": response.finishReason,
            ])
            return response
        } catch let error as ProviderRuntimeError {
            applyFailure(error)
            throw error
        } catch is CancellationError {
            applyFailure(.cancelled)
            throw ProviderRuntimeError.cancelled
        } catch {
            applyFailure(.unknown)
            throw ProviderRuntimeError.unknown
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await self.prepareExecution()
                    await self.emitInvoked(model: request.model, mode: "stream")
                    let bound = await self.currentProvider()
                    for try await event in bound.stream(request) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                        if case .completed = event {
                            await self.markCompleted()
                        }
                    }
                    await self.markCompletedIfExecuting()
                    continuation.finish()
                } catch is CancellationError {
                    await self.applyFailure(.cancelled)
                    continuation.finish(throwing: ProviderRuntimeError.cancelled)
                } catch let error as ProviderRuntimeError {
                    await self.applyFailure(error)
                    continuation.finish(throwing: error)
                } catch {
                    await self.applyFailure(.unknown)
                    continuation.finish(throwing: ProviderRuntimeError.unknown)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    public func cancel() {
        if lifecycle == .executing {
            applyFailure(.cancelled)
        }
    }

    private func currentProvider() -> any LLMProvider { provider }

    private func emitInvoked(model: ModelID, mode: String) {
        emit(kind: .providerInvoked, payload: [
            "providerID": provider.identity.id.rawValue,
            "model": model.rawValue,
            "mode": mode,
        ])
    }

    private func markCompleted() {
        lifecycle = .completed
    }

    private func markCompletedIfExecuting() {
        if lifecycle == .executing {
            lifecycle = .completed
        }
    }

    private func prepareExecution() throws {
        guard lifecycle == .ready || lifecycle == .completed || lifecycle == .failed || lifecycle == .cancelled else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        lifecycle = .executing
    }

    private func applyFailure(_ error: ProviderRuntimeError) {
        if error == .cancelled {
            lifecycle = .cancelled
            emit(kind: .providerCancelled, payload: ["providerID": provider.identity.id.rawValue])
        } else {
            lifecycle = .failed
            emit(kind: .providerFailed, payload: [
                "providerID": provider.identity.id.rawValue,
                "error": error.description,
            ])
        }
    }

    private func execute<T: Sendable>(
        timeoutNanoseconds: UInt64?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            if let timeoutNanoseconds, timeoutNanoseconds > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw ProviderRuntimeError.timeout
                }
            }
            guard let first = try await group.next() else {
                throw ProviderRuntimeError.unknown
            }
            group.cancelAll()
            return first
        }
    }

    private func emit(kind: ExecutionEventKind, payload: [String: String]) {
        let sanitized = SecretRedactor.stripSecrets(from: payload)
        logger.log(
            LogEvent(
                level: kind == .providerFailed || kind == .providerCancelled ? .warning : .info,
                category: "provider",
                message: kind.rawValue,
                metadata: sanitized
            )
        )
        guard let eventLog else { return }
        let event = ExecutionEvent(
            traceID: sessionTrace,
            kind: kind,
            payload: sanitized
        )
        Task {
            try? await eventLog.append(event)
        }
    }
}

public struct ProviderNullLogger: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}

public enum SecretRedactor: Sendable {
    public static func stripSecrets(from payload: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in payload {
            if ProviderTransportRequest.sensitiveHeaderKeys.contains(key.lowercased())
                || key.lowercased().contains("secret")
                || key.lowercased().contains("token")
                || key.lowercased().contains("authorization")
            {
                result[key] = "<redacted>"
            } else {
                result[key] = value
            }
        }
        return result
    }

    public static func containsSensitiveLiteral(_ text: String, secrets: [String]) -> Bool {
        secrets.contains { !$0.isEmpty && text.contains($0) }
    }
}
