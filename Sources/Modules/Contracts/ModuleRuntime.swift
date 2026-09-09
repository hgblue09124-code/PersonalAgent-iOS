import Foundation
import PAFoundation
import PAObservability
import PAEvents

/// Coordinates module execution. Isolated from AgentRuntime and ProviderRuntime.
public actor ModuleRuntime: ModuleExecuting {
    public let grantedCapabilities: CapabilityLevel
    private let catalog: ModuleCatalog
    private let eventLog: (any EventLog)?
    private let logger: any AgentLogger
    private let sessionTrace: TraceID
    private let defaultTimeoutNanoseconds: UInt64

    public init(
        catalog: ModuleCatalog,
        grantedCapabilities: CapabilityLevel,
        eventLog: (any EventLog)? = nil,
        logger: any AgentLogger = ModuleNullLogger(),
        sessionTrace: TraceID = TraceID(),
        defaultTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.catalog = catalog
        self.grantedCapabilities = grantedCapabilities
        self.eventLog = eventLog
        self.logger = logger
        self.sessionTrace = sessionTrace
        self.defaultTimeoutNanoseconds = defaultTimeoutNanoseconds
    }

    public func contracts() async -> [ModuleContract] {
        await catalog.contracts()
    }

    public func execute(_ invocation: ModuleInvocation) async throws -> ModuleResult {
        if Task.isCancelled {
            throw ModuleRuntimeError.cancelled
        }
        guard let module = await catalog.resolve(invocation.moduleID) else {
            emit(kind: .moduleFailed, payload: [
                "moduleID": invocation.moduleID.rawValue,
                "error": ModuleRuntimeError.unknownModule(invocation.moduleID).description,
            ])
            throw ModuleRuntimeError.unknownModule(invocation.moduleID)
        }
        let contract = module.contract
        if contract.lifecycle == .unloaded || contract.lifecycle == .failed {
            throw ModuleRuntimeError.unavailable(contract.id)
        }
        if !grantedCapabilities.contains(contract.capabilities) {
            emit(kind: .moduleFailed, payload: [
                "moduleID": contract.id.rawValue,
                "error": ModuleRuntimeError.capabilityDenied(contract.capabilities).description,
            ])
            throw ModuleRuntimeError.capabilityDenied(contract.capabilities)
        }
        try validate(invocation.input, against: contract)

        emit(kind: .moduleInvoked, payload: [
            "moduleID": contract.id.rawValue,
            "kind": contract.kind.rawValue,
        ])

        let timeout = invocation.timeoutNanoseconds ?? defaultTimeoutNanoseconds
        do {
            let output = try await run(module: module, input: invocation.input, timeout: timeout)
            emit(kind: .moduleCompleted, payload: ["moduleID": contract.id.rawValue])
            return ModuleResult(moduleID: contract.id, output: output, state: .completed)
        } catch is CancellationError {
            emit(kind: .moduleCancelled, payload: ["moduleID": contract.id.rawValue])
            throw ModuleRuntimeError.cancelled
        } catch let error as ModuleRuntimeError {
            if error == .cancelled {
                emit(kind: .moduleCancelled, payload: ["moduleID": contract.id.rawValue])
            } else if error == .timeout {
                emit(kind: .moduleFailed, payload: [
                    "moduleID": contract.id.rawValue,
                    "error": error.description,
                ])
            } else {
                emit(kind: .moduleFailed, payload: [
                    "moduleID": contract.id.rawValue,
                    "error": error.description,
                ])
            }
            throw error
        } catch {
            let wrapped = ModuleRuntimeError.executionFailed("module")
            emit(kind: .moduleFailed, payload: [
                "moduleID": contract.id.rawValue,
                "error": wrapped.description,
            ])
            throw wrapped
        }
    }

    private func validate(_ input: ModulePayload, against contract: ModuleContract) throws {
        if input.schema.identifier != contract.inputSchema.identifier {
            throw ModuleRuntimeError.invalidInput("schema")
        }
        for field in contract.requiredFields {
            let value = input.fields[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                throw ModuleRuntimeError.invalidInput(field)
            }
        }
    }

    private func run(
        module: any Module,
        input: ModulePayload,
        timeout: UInt64
    ) async throws -> ModulePayload {
        try await withThrowingTaskGroup(of: ModulePayload.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await module.execute(input)
            }
            if timeout > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    throw ModuleRuntimeError.timeout
                }
            }
            guard let first = try await group.next() else {
                throw ModuleRuntimeError.executionFailed("empty")
            }
            group.cancelAll()
            return first
        }
    }

    private func emit(kind: ExecutionEventKind, payload: [String: String]) {
        logger.log(
            LogEvent(
                level: kind == .moduleFailed || kind == .moduleCancelled ? .warning : .info,
                category: "module",
                message: kind.rawValue,
                metadata: payload
            )
        )
        guard let eventLog else { return }
        let event = ExecutionEvent(traceID: sessionTrace, kind: kind, payload: payload)
        Task {
            try? await eventLog.append(event)
        }
    }
}

public struct ModuleNullLogger: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
