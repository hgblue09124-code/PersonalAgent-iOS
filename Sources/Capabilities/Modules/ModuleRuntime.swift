import Foundation
import PAFoundation
import PAObservability
import PAEvents

/// Coordinates module execution. Isolated from AgentRuntime and ProviderRuntime.
///
/// Timeout and cancellation are cooperative. `Module.execute` must honor
/// `Task.checkCancellation()` at suspension points. An uncooperative body that
/// never awaits cannot be hard-preempted by Swift concurrency; the caller still
/// receives `.timeout` / `.cancelled` and the runtime never emits
/// `.moduleCompleted` for that invocation.
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
            await emit(kind: .moduleFailed, payload: [
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
            await emit(kind: .moduleFailed, payload: [
                "moduleID": contract.id.rawValue,
                "error": ModuleRuntimeError.capabilityDenied(contract.capabilities).description,
            ])
            throw ModuleRuntimeError.capabilityDenied(contract.capabilities)
        }
        try validateInput(invocation.input, against: contract)

        await emit(kind: .moduleInvoked, payload: [
            "moduleID": contract.id.rawValue,
            "kind": contract.kind.rawValue,
        ])

        let timeout = invocation.timeoutNanoseconds ?? defaultTimeoutNanoseconds
        do {
            let output = try await run(module: module, input: invocation.input, timeout: timeout)
            try validateOutput(output, against: contract)
            await emit(kind: .moduleCompleted, payload: ["moduleID": contract.id.rawValue])
            return ModuleResult(moduleID: contract.id, output: output, state: .completed)
        } catch is CancellationError {
            await emit(kind: .moduleCancelled, payload: ["moduleID": contract.id.rawValue])
            throw ModuleRuntimeError.cancelled
        } catch let error as ModuleRuntimeError {
            if error == .cancelled {
                await emit(kind: .moduleCancelled, payload: ["moduleID": contract.id.rawValue])
            } else {
                await emit(kind: .moduleFailed, payload: [
                    "moduleID": contract.id.rawValue,
                    "error": error.description,
                ])
            }
            throw error
        } catch {
            let wrapped = ModuleRuntimeError.executionFailed("module")
            await emit(kind: .moduleFailed, payload: [
                "moduleID": contract.id.rawValue,
                "error": wrapped.description,
            ])
            throw wrapped
        }
    }

    private func validateInput(_ input: ModulePayload, against contract: ModuleContract) throws {
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

    private func validateOutput(_ output: ModulePayload, against contract: ModuleContract) throws {
        if output.schema.identifier != contract.outputSchema.identifier {
            throw ModuleRuntimeError.invalidOutput("schema")
        }
    }

    private func run(
        module: any Module,
        input: ModulePayload,
        timeout: UInt64
    ) async throws -> ModulePayload {
        try await withThrowingTaskGroup(of: RunOutcome.self) { group in
            group.addTask {
                try Task.checkCancellation()
                let payload = try await module.execute(input)
                return .finished(payload)
            }
            if timeout > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: timeout)
                    return .timedOut
                }
            }
            guard let first = try await group.next() else {
                throw ModuleRuntimeError.executionFailed("empty")
            }
            group.cancelAll()
            switch first {
            case .finished(let payload):
                return payload
            case .timedOut:
                throw ModuleRuntimeError.timeout
            }
        }
    }

    private func emit(kind: ExecutionEventKind, payload: [String: String]) async {
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
        try? await eventLog.append(event)
    }
}

private enum RunOutcome: Sendable {
    case finished(ModulePayload)
    case timedOut
}

public struct ModuleNullLogger: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
