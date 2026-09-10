import Foundation
import Testing
import PAFoundation
import PAModules
import PATools
import PASkills
import PAEvents

@Suite("M3 repaired semantics")
struct M3SemanticsTests {
    @Test func cooperativeTimeoutDoesNotEmitCompleted() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [HangModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        await #expect(throws: ModuleRuntimeError.timeout) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 20_000_000
                )
            )
        }
        let kinds = await log.kinds()
        #expect(kinds.contains(.moduleInvoked))
        #expect(kinds.contains(.moduleFailed))
        #expect(!kinds.contains(.moduleCompleted))
    }

    @Test func cancellationDuringHangDoesNotEmitCompleted() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [HangModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.hang,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.hang.in")),
                    timeoutNanoseconds: 60_000_000_000
                )
            )
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancel")
        } catch is CancellationError {
        } catch let error as ModuleRuntimeError {
            #expect(error == .cancelled || error == .timeout)
        }
        let kinds = await log.kinds()
        #expect(!kinds.contains(.moduleCompleted))
    }

    @Test func cancellationResistantModuleStillTimesOutWithoutCompleted() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [CancellationResistantModule(spinNanoseconds: 1_000_000_000)])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        await #expect(throws: ModuleRuntimeError.timeout) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.resistant,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.resistant.in")),
                    timeoutNanoseconds: 10_000_000
                )
            )
        }
        let kinds = await log.kinds()
        #expect(!kinds.contains(.moduleCompleted))
        #expect(kinds.contains(.moduleFailed))
    }

    @Test func missingDependencyRejectedAtRegistration() {
        #expect(throws: ModuleRuntimeError.missingDependency(
            module: DeterministicModuleIDs.needsMissing,
            missing: ModuleID(rawValue: "mod.does-not-exist")
        )) {
            _ = try ModuleCatalog(modules: [MissingDependencyModule()])
        }
    }

    @Test func dependencyCycleRejected() {
        do {
            _ = try ModuleCatalog(modules: [CycleAModule(), CycleBModule()])
            Issue.record("expected cycle")
        } catch let error as ModuleRuntimeError {
            guard case .dependencyCycle(let ids) = error else {
                Issue.record("wrong \(error)")
                return
            }
            #expect(ids.contains(DeterministicModuleIDs.cycleA))
            #expect(ids.contains(DeterministicModuleIDs.cycleB))
        } catch {
            Issue.record("wrong \(error)")
        }
    }

    @Test func dependencyOrderIsDeterministic() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        try await catalog.register(EchoSkillModule(runtime: runtime))
        let order = try await catalog.dependencyOrder(of: DeterministicModuleIDs.compose)
        #expect(order == [DeterministicModuleIDs.echo, DeterministicModuleIDs.compose])
        let again = try await catalog.dependencyOrder(of: DeterministicModuleIDs.compose)
        #expect(order == again)
    }

    @Test func outputSchemaMismatchRejected() async throws {
        let catalog = try ModuleCatalog(modules: [WrongOutputModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        await #expect(throws: ModuleRuntimeError.invalidOutput("schema")) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.wrongOutput,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.wrong-output.in"))
                )
            )
        }
    }

    @Test func skillExecutionGoesThroughModuleRuntime() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        try await catalog.register(EchoSkillModule(runtime: runtime))
        let result = try await runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.compose,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "via-skill"])
            )
        )
        #expect(result.output.value(for: "text") == "via-skill")
        let events = await log.allEvents()
        let invoked = events.filter { $0.kind == .moduleInvoked }.compactMap { $0.payload["moduleID"] }
        #expect(invoked.contains("skill.echo"))
        #expect(invoked.contains("mod.echo"))
    }

    @Test func skillFailurePropagatesThroughRuntime() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [FailingEchoModule()])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        try await catalog.register(EchoSkillModule(runtime: runtime, childID: DeterministicModuleIDs.failEcho))
        do {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.compose,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "x"])
                )
            )
            Issue.record("expected composition failure")
        } catch let error as ModuleRuntimeError {
            guard case .compositionFailed(let reason) = error else {
                Issue.record("wrong \(error)")
                return
            }
            #expect(reason.contains("executionFailed:skill-child"))
        }
        let events = await log.allEvents()
        let invoked = events.filter { $0.kind == .moduleInvoked }.compactMap { $0.payload["moduleID"] }
        #expect(invoked.contains("skill.echo"))
        #expect(invoked.contains("mod.fail-echo"))
        #expect(!events.map(\.kind).contains(.moduleCompleted))
    }

    @Test func toolExecutesThroughModuleRuntime() async throws {
        let catalog = try ModuleCatalog(modules: [ToolModule(tool: EchoTool())])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
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

    @Test func toolCapabilityDenied() async throws {
        let catalog = try ModuleCatalog(modules: [ToolModule(tool: PrivilegedTool())])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        await #expect(throws: ModuleRuntimeError.capabilityDenied(.destructive)) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: ModuleID(rawValue: "tool.privileged"),
                    input: ModulePayload(
                        schema: SchemaDocument(identifier: "tool.privileged.in"),
                        fields: ["arguments": "x"]
                    )
                )
            )
        }
    }

    @Test func incrementalMissingDependencyRejected() async {
        let catalog = ModuleCatalog()
        await #expect(throws: ModuleRuntimeError.missingDependency(
            module: DeterministicModuleIDs.needsMissing,
            missing: ModuleID(rawValue: "mod.does-not-exist")
        )) {
            try await catalog.register(MissingDependencyModule())
        }
    }

    @Test func cancellationResistantModuleCallerCancelDoesNotComplete() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [CancellationResistantModule(spinNanoseconds: 80_000_000)])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.resistant,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.resistant.in")),
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
        let kinds = await log.kinds()
        #expect(!kinds.contains(.moduleCompleted))
    }

    @Test func toolTimeoutDoesNotComplete() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [ToolModule(tool: HangTool())])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        await #expect(throws: ModuleRuntimeError.timeout) {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: ModuleID(rawValue: "tool.hang"),
                    input: ModulePayload(
                        schema: SchemaDocument(identifier: "tool.hang.in"),
                        fields: ["arguments": "x"]
                    ),
                    timeoutNanoseconds: 20_000_000
                )
            )
        }
        let kinds = await log.kinds()
        #expect(!kinds.contains(.moduleCompleted))
    }

    @Test func toolCancellationDoesNotComplete() async throws {
        let log = InMemoryEventLog()
        let catalog = try ModuleCatalog(modules: [ToolModule(tool: HangTool())])
        let runtime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            eventLog: log
        )
        let task = Task {
            try await runtime.execute(
                ModuleInvocation(
                    moduleID: ModuleID(rawValue: "tool.hang"),
                    input: ModulePayload(
                        schema: SchemaDocument(identifier: "tool.hang.in"),
                        fields: ["arguments": "x"]
                    ),
                    timeoutNanoseconds: 60_000_000_000
                )
            )
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancel")
        } catch is CancellationError {
        } catch let error as ModuleRuntimeError {
            #expect(error == .cancelled || error == .timeout)
        }
        let kinds = await log.kinds()
        #expect(!kinds.contains(.moduleCompleted))
    }

    @Test func repeatedDeterministicExecution() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule(), ToolModule(tool: EchoTool())])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        let echo = ModuleInvocation(
            moduleID: DeterministicModuleIDs.echo,
            input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "same"])
        )
        let first = try await runtime.execute(echo)
        let second = try await runtime.execute(echo)
        #expect(first.output == second.output)
        let tool = ModuleInvocation(
            moduleID: ModuleID(rawValue: "tool.echo"),
            input: ModulePayload(schema: SchemaDocument(identifier: "tool.echo.in"), fields: ["arguments": "same"])
        )
        let toolFirst = try await runtime.execute(tool)
        let toolSecond = try await runtime.execute(tool)
        #expect(toolFirst.output == toolSecond.output)
    }
}
