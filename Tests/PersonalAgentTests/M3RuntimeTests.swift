import Foundation
import Testing
import PAFoundation
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
            grantedCapabilities: [.read, .write, .execute]
        )
    }
}
