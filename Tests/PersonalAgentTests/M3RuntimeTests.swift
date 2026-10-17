import Foundation
import Testing
import PAKernel
import PAEvents
import PAModules
import PATools
import PASkills

@Suite("M3 module runtime")
struct M3RuntimeTests {
    @Test func echoSucceeds() async throws {
        let runtime = try await armed()
        let result = try await runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.echo,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "ping"])
            )
        )
        #expect(result.output.value(for: "text") == "ping")
        #expect(result.state == .completed)
    }

    @Test func unknownModuleFails() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.unknownModule(ModuleID(rawValue: "missing"))) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: ModuleID(rawValue: "missing"),
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"))
                )
            )
        }
    }

    @Test func invalidInputRejected() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.invalidInput("text")) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: [:])
                )
            )
        }
    }

    @Test func schemaMismatchRejected() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.invalidInput("schema")) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "other"), fields: ["text": "x"])
                )
            )
        }
    }

    @Test func liveSettingsPolicyDeniesDirectModuleExecution() async throws {
        struct DenyExecutionPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                intent.capabilities.contains(.execute) ? .deny("execution disabled in Settings") : .allow("read permitted")
            }
        }
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            policy: DenyExecutionPolicy()
        )
        await #expect(throws: ModuleRuntimeError.capabilityDenied([.read, .execute])) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "blocked"])
                )
            )
        }
    }


    @Test func approvalRequiredModuleExecutesOnlyAfterExplicitApproval() async throws {
        struct ApprovalRequiredPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                .approve("explicit module approval required")
            }
        }
        struct ApprovingGate: ApprovalGate {
            func requestApproval(for intent: ActionIntent) async throws -> Bool {
                intent.capabilities == [.read, .execute] &&
                    intent.summary.hasPrefix("Execute Module ")
            }
        }
        let eventLog = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            policy: ApprovalRequiredPolicy(),
            approvalGate: ApprovingGate(),
            eventLog: eventLog
        )
        let result = try await runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.echo,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "approved"])
            )
        )
        #expect(result.output.value(for: "text") == "approved")
        let events = try await eventLog.allEvents()
        #expect(events.contains { $0.kind == .moduleInvoked })
        #expect(events.contains { $0.kind == .moduleCompleted })
    }

    @Test func approvalRequiredModuleStillFailsClosedWhenRejected() async throws {
        struct ApprovalRequiredPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                .approve("explicit module approval required")
            }
        }
        struct RejectingGate: ApprovalGate {
            func requestApproval(for intent: ActionIntent) async throws -> Bool { false }
        }
        let eventLog = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            policy: ApprovalRequiredPolicy(),
            approvalGate: RejectingGate(),
            eventLog: eventLog
        )
        await #expect(throws: ModuleRuntimeError.capabilityDenied([.read, .execute])) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "rejected"])
                )
            )
        }
        let events = try await eventLog.allEvents()
        #expect(events.contains { $0.kind == .moduleFailed })
        #expect(!events.contains { $0.kind == .moduleInvoked })
    }


    @Test func cancellationDuringApprovalNeverInvokesModule() async throws {
        struct ApprovalRequiredPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                .approve("explicit module approval required")
            }
        }
        let gate = ApprovalGateLatch()
        let eventLog = InMemoryEventLog()
        let runtime = ModuleRuntime(
            catalog: try ModuleCatalog(modules: [EchoModule()]),
            grantedCapabilities: [.read, .execute],
            policy: ApprovalRequiredPolicy(),
            approvalGate: gate,
            eventLog: eventLog
        )
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "cancelled"])
                )
            )
        }
        await gate.waitUntilRequested()
        task.cancel()
        await gate.resolve(true)
        do {
            _ = try await task.value
            Issue.record("cancelled approval must not execute the module")
        } catch let error as ModuleRuntimeError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("expected ModuleRuntimeError.cancelled, got \(error)")
        }
        let events = try await eventLog.allEvents()
        #expect(events.contains { $0.kind == .moduleCancelled })
        #expect(!events.contains { $0.kind == .moduleInvoked })
    }

    @Test func missingPolicyFailsClosed() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        await #expect(throws: ModuleRuntimeError.capabilityDenied([.read, .execute])) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "blocked"])
                )
            )
        }
    }

    @Test func capabilityDenied() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.capabilityDenied(.destructive)) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.privileged,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.privileged.in"))
                )
            )
        }
    }

    @Test func unloadedModuleIsUnavailable() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.unavailable(DeterministicModuleIDs.unloaded)) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.unloaded,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.unloaded.in"))
                )
            )
        }
    }

    @Test func timeoutDuringExecution() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.timeout) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 20_000_000
                )
            )
        }
    }

    @Test func cancellationBeforeExecution() async throws {
        let runtime = try await armed()
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "late"])
                )
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancel")
        } catch is CancellationError {
        } catch let error as ModuleRuntimeError {
            #expect(error == .cancelled)
        }
    }

    @Test func cancellationDuringExecution() async throws {
        let runtime = try await armed()
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 60_000_000_000
                )
            )
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancel")
        } catch is CancellationError {
        } catch let error as ModuleRuntimeError {
            #expect(error == .cancelled || error == .timeout)
        }
    }

    @Test func concurrentCancellation() async throws {
        let runtime = try await armed()
        let first = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 60_000_000_000
                )
            )
        }
        let second = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 60_000_000_000
                )
            )
        }
        first.cancel()
        second.cancel()
        for task in [first, second] {
            do {
                _ = try await task.value
                Issue.record("expected cancel")
            } catch is CancellationError {
            } catch let error as ModuleRuntimeError {
                #expect(error == .cancelled || error == .timeout)
            }
        }
    }

    @Test func deterministicFailure() async throws {
        let runtime = try await armed()
        await #expect(throws: ModuleRuntimeError.executionFailed("deterministic")) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.fail,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.fail.in"))
                )
            )
        }
    }

    @Test func repeatedEchoIsDeterministic() async throws {
        let runtime = try await armed()
        let invocation = ModuleInvocation(
            moduleID: DeterministicModuleIDs.echo,
            input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "same"])
        )
        let first = try await runtime.execute(invocation)
        let second = try await runtime.execute(invocation)
        #expect(first.output == second.output)
    }

    @Test func toolModuleExecutesThroughAdapter() async throws {
        let catalog = try ModuleCatalog(modules: [ToolModule(tool: EchoTool())])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute], policy: AllowModuleRuntimePolicy())
        let result = try await runtime.execute(
            ModuleInvocation(
                moduleID: ModuleID(rawValue: "tool.echo"),
                input: ModulePayload(
                    schema: SchemaDocument(identifier: "tool.echo.in"),
                    fields: ["arguments": "hello"]
                )
            )
        )
        #expect(result.output.value(for: "output") == "hello")
        #expect(result.state == .completed)
    }

    private func armed() async throws -> ModuleRuntime {
        let catalog = try ModuleCatalog(modules: [
            EchoModule(),
            ValidationRejectModule(),
            PrivilegedModule(),
            HangModule(),
            FailingModule(),
            UnloadedModule(),
        ])
        return ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .write, .execute],
            policy: AllowModuleRuntimePolicy()
        )
    }
}

private struct AllowModuleRuntimePolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("explicit test grant") }
}


private actor ApprovalGateLatch: ApprovalGate {
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var requested = false

    func requestApproval(for intent: ActionIntent) async throws -> Bool {
        requested = true
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resolve(_ approved: Bool) {
        approvalContinuation?.resume(returning: approved)
        approvalContinuation = nil
    }
}
