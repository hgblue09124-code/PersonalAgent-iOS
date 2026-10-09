import Foundation
import PAKernel
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
        let race = RunRace()

        let outcome: RunOutcome = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RunOutcome, any Error>) in
                race.install(continuation)

                let worker = Task {
                    do {
                        try Task.checkCancellation()
                        let payload = try await module.execute(input)
                        race.resolve(.success(.finished(payload)))
                    } catch let error as ModuleRuntimeError {
                        race.resolve(.failure(error))
                    } catch is CancellationError {
                        race.resolve(.failure(.cancelled))
                    } catch {
                        race.resolve(.failure(.executionFailed("module")))
                    }
                }

                let timer: Task<Void, Never>? = timeout > 0 ? Task {
                    do {
                        try await Task.sleep(nanoseconds: timeout)
                        race.resolve(.success(.timedOut))
                    } catch {
                        race.resolve(.failure(.cancelled))
                    }
                } : nil

                race.attach(worker: worker, timer: timer)

                if timeout == 0 {
                    race.resolve(.success(.timedOut))
                }
            }
        } onCancel: {
            race.resolve(.failure(.cancelled))
        }

        switch outcome {
        case .finished(let payload):
            return payload
        case .timedOut:
            throw ModuleRuntimeError.timeout
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

private final class RunRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RunOutcome, any Error>?
    private var result: Result<RunOutcome, any Error>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    func install(_ continuation: CheckedContinuation<RunOutcome, any Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func attach(worker: Task<Void, Never>, timer: Task<Void, Never>?) {
        lock.lock()
        if result != nil {
            lock.unlock()
            worker.cancel()
            timer?.cancel()
            return
        }
        self.worker = worker
        self.timer = timer
        lock.unlock()
    }

    func resolve(_ result: Result<RunOutcome, any Error>) {
        lock.lock()
        if self.result != nil {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let worker = self.worker
        let timer = self.timer
        lock.unlock()

        worker?.cancel()
        timer?.cancel()
        continuation?.resume(with: result)
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
