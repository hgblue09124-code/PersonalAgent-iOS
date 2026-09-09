import Testing
import PAFoundation
import PAArchitecture
import PAComposition
import PAKernel
import PAModules
import PAEvents

@Suite("M3 composition and isolation")
struct M3CompositionIsolationTests {
    @Test func rootWiresModuleRuntimeWithoutPrivilegedGrant() async {
        let root = await M3CompositionRoot(
            identity: AgentIdentity(id: AgentID(rawValue: "m3"), displayName: "Personal")
        )
        #expect(root.milestone == .m3)
        #expect(root.milestone.skillRuntime)
        #expect(root.milestone.toolRuntime)
        #expect(await root.runtime.coordination.isWiredForModules)
        let ids = await root.registeredModuleIDs()
        #expect(ids.contains("mod.echo"))
        #expect(ids.contains("skill.echo"))
        #expect(ids.contains("tool.echo"))
        await #expect(throws: ModuleRuntimeError.capabilityDenied(.destructive)) {
            _ = try await root.moduleRuntime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.privileged,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.privileged.in"))
                )
            )
        }
        #expect(await root.runtime.currentState().lifecycle == .created)
    }

    @Test func skillComposesEcho() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        try await catalog.register(EchoSkillModule(runtime: runtime))
        let ok = try await runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.compose,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "via-skill"])
            )
        )
        #expect(ok.output.value(for: "text") == "via-skill")
    }

    @Test func skillFailurePropagates() async throws {
        let catalog = try ModuleCatalog(modules: [FailingModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        try await catalog.register(EchoSkillModule(runtime: runtime, childID: DeterministicModuleIDs.fail))
        do {
            _ = try await runtime.execute(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.compose,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "x"])
                )
            )
            Issue.record("expected composition failure")
        } catch let error as ModuleRuntimeError {
            guard case .compositionFailed = error else {
                Issue.record("wrong \(error)")
                return
            }
        }
    }

    @Test func concurrentExecutionDoesNotCorruptCatalog() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let runtime = ModuleRuntime(catalog: catalog, grantedCapabilities: [.read, .execute])
        async let a = runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.echo,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "A"])
            )
        )
        async let b = runtime.execute(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.echo,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "B"])
            )
        )
        let pair = try await (a, b)
        #expect(Set([pair.0.output.value(for: "text"), pair.1.output.value(for: "text")]) == ["A", "B"])
        #expect(await catalog.contracts().count == 1)
    }

    @Test func kernelSourcesDoNotMentionConcreteTestModules() throws {
        let kernelDir = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Core")
            .appendingPathComponent("Agent")
        let files = try files(under: kernelDir, suffix: ".swift")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("EchoModule"))
            #expect(!text.contains("PrivilegedModule"))
            #expect(!text.contains("PAProvidersGrok"))
            #expect(!text.contains("SwiftUI"))
        }
    }

    @Test func kernelInvokeRequiresRunningLifecycleAndPreservesInvariants() async throws {
        let root = await M3CompositionRoot(
            identity: AgentIdentity(id: AgentID(rawValue: "m3-invoke"), displayName: "Personal")
        )
        await #expect(throws: KernelError.runtimeNotExecutable(.created)) {
            _ = try await root.runtime.invokeModule(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "early"])
                )
            )
        }
        #expect(await root.runtime.invariantsHold())
        try await root.runtime.start()
        let result = try await root.runtime.invokeModule(
            ModuleInvocation(
                moduleID: DeterministicModuleIDs.echo,
                input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "via-kernel"])
            )
        )
        #expect(result.output.value(for: "text") == "via-kernel")
        #expect(await root.runtime.invariantsHold())
        await #expect(throws: ModuleRuntimeError.executionFailed("deterministic")) {
            _ = try await root.runtime.invokeModule(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.fail,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.fail.in"))
                )
            )
        }
        #expect(await root.runtime.currentState().lifecycle == .running)
        #expect(await root.runtime.invariantsHold())
        try await root.runtime.stop()
        await #expect(throws: KernelError.runtimeNotExecutable(.stopped)) {
            _ = try await root.runtime.invokeModule(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "late"])
                )
            )
        }
        #expect(await root.runtime.invariantsHold())
    }

    @Test func unwiredKernelRejectsModulePort() async throws {
        let runtime = await AgentRuntime(
            identity: AgentIdentity(displayName: "bare"),
            eventLog: InMemoryEventLog()
        )
        try await runtime.start()
        await #expect(throws: KernelError.modulePortUnavailable) {
            _ = try await runtime.invokeModule(
                ModuleInvocation(
                    moduleID: DeterministicModuleIDs.echo,
                    input: ModulePayload(schema: SchemaDocument(identifier: "mod.echo.in"), fields: ["text": "x"])
                )
            )
        }
        #expect(await runtime.invariantsHold())
    }

    @Test func moduleSourcesDoNotImportConcreteProvidersOrUI() throws {
        let root = repositoryRoot().appendingPathComponent("Sources").appendingPathComponent("Modules")
        let files = try files(under: root, suffix: ".swift")
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!importedModules(in: text).contains("SwiftUI"))
            #expect(!importedModules(in: text).contains("PAProvidersGrok"))
            #expect(!importedModules(in: text).contains("PAProvidersOpenAI"))
            #expect(!text.contains("URLSession"))
            #expect(!text.contains("static let shared"))
            #expect(!text.contains("ServiceLocator"))
        }
    }
}
