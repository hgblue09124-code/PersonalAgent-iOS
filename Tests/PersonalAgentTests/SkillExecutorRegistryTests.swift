import Testing
import PAKernel
import PARuntime
import PASkills
import PAModules

@Suite("Skill Executor Registry")
struct SkillExecutorRegistryTests {
    struct EchoExecutor: SkillExecutor {
        func execute(manifest: SkillManifest, inputJSON: String) async throws -> String { "{\"value\":\"custom\"}" }
        func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool { outputJSON.contains("custom") }
    }
    struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("allowed") }
    }

    @Test("runtime executes through registered executor")
    func customExecutorRuns() async throws {
        let id = SkillID(rawValue: "custom.echo")
        let manifest = SkillManifest(
            id: id, name: "Custom Echo", description: "A custom test skill.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return a custom value.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read, .execute]
        )
        let store = InMemorySkillStore(manifests: [manifest])
        let registry = SkillExecutorRegistry()
        await registry.register(EchoExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: store, executors: registry)
        let output = try await runtime.execute(id: id, inputJSON: "{\"value\":\"input\"}", policy: AllowPolicy())
        #expect(output == "{\"value\":\"custom\"}")
        #expect(try await runtime.verify(id: id, outputJSON: output))
    }

    @Test("Skill manifest can execute through the policy-gated ModuleRuntime")
    func moduleBackedSkillExecutesAndVerifies() async throws {
        let id = SkillID(rawValue: "custom.echo")
        let manifest = SkillManifest(
            id: id,
            name: "Module Echo",
            description: "Echo through ModuleRuntime.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Echo text.",
            inputSchema: SchemaDocument(identifier: "mod.echo.in"),
            outputSchema: SchemaDocument(identifier: "mod.echo.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["moduleID": DeterministicModuleIDs.echo.rawValue]
        )
        let catalog = try ModuleCatalog(modules: [EchoModule()])
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .execute],
            policy: AllowPolicy()
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )
        let output = try await runtime.execute(
            id: id,
            inputJSON: "{\"text\":\"hello\"}",
            policy: AllowPolicy()
        )
        #expect(output == "{\"text\":\"hello\"}")
        #expect(try await runtime.verify(id: id, outputJSON: output))
    }

    @Test("declared built-in executor resolves for an imported Skill ID")
    func declaredBuiltinExecutorRunsForImportedSkillID() async throws {
        let id = SkillID(rawValue: "custom.normalize")
        let manifest = SkillManifest(
            id: id,
            name: "Normalize Imported Text",
            description: "Uses the explicitly declared built-in text normalizer.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Trim surrounding whitespace.",
            inputSchema: SchemaDocument(identifier: "skill.custom.normalize.in"),
            outputSchema: SchemaDocument(identifier: "skill.custom.normalize.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["executor": "text.normalize"]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        let output = try await runtime.execute(
            id: id,
            inputJSON: #"{"text":"  hello  "}"#,
            policy: AllowPolicy()
        )
        #expect(output == #"{"text":"hello"}"#)
        #expect(try await runtime.verify(id: id, outputJSON: output))
    }

    @Test("module-backed Skill rejects a manifest that lies about module schemas")
    func moduleBackedSkillRejectsSchemaMismatch() async throws {
        let id = SkillID(rawValue: "custom.echo")
        let manifest = SkillManifest(
            id: id,
            name: "Mismatched Echo",
            description: "Its declared output contract does not match the Module.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Echo text.",
            inputSchema: SchemaDocument(identifier: "mod.echo.in"),
            outputSchema: SchemaDocument(identifier: "skill.fake.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["moduleID": DeterministicModuleIDs.echo.rawValue]
        )
        let moduleRuntime = ModuleRuntime(
            catalog: try ModuleCatalog(modules: [EchoModule()]),
            grantedCapabilities: [.read, .execute],
            policy: AllowPolicy()
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )

        await #expect(throws: SkillRuntimeError.malformedSkill) {
            try await runtime.execute(
                id: id,
                inputJSON: #"{"text":"hello"}"#,
                policy: AllowPolicy()
            )
        }
        #expect(try await runtime.verify(id: id, outputJSON: #"{"text":"hello"}"#) == false)
    }

    @Test("late executor output is rejected after cancellation")
    func lateExecutorOutputFailsAfterCancellation() async throws {
        let id = SkillID(rawValue: "custom.deferred")
        let manifest = SkillManifest(
            id: id,
            name: "Deferred Executor",
            description: "A test executor that does not cooperate with cancellation.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return a deferred result.",
            inputSchema: SchemaDocument(identifier: "deferred.in"),
            outputSchema: SchemaDocument(identifier: "deferred.out"),
            requiredCapabilities: [.read, .execute]
        )
        let gate = DeferredSkillOutput()
        let registry = SkillExecutorRegistry()
        await registry.register(DeferredExecutor(gate: gate), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)
        let task = Task {
            try await runtime.execute(id: id, inputJSON: #"{"text":"request"}"#, policy: AllowPolicy())
        }

        await gate.waitUntilStarted()
        task.cancel()
        await gate.resume(#"{"text":"late"}"#)
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("missing executor fails closed")
    func missingExecutorFailsClosed() async {
        let id = SkillID(rawValue: "custom.missing")
        let manifest = SkillManifest(
            id: id, name: "Missing Executor", description: "No executor registered.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "No execution.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: SkillExecutorRegistry())
        await #expect(throws: SkillRuntimeError.unknownSkill(id)) {
            try await runtime.execute(id: id, inputJSON: "{\"value\":\"input\"}", policy: AllowPolicy())
        }
    }
    @Test("chat skill input separates instruction from explicit payload")
    func chatSkillInputUsesExplicitPayload() {
        #expect(SkillRuntime.chatInputText(from: "normalize this text:   hello  ") == "  hello  ")
        #expect(SkillRuntime.chatInputText(from: "normalize this text") == "normalize this text")
        #expect(SkillRuntime.chatInputText(from: "open https://example.com") == "open https://example.com")
    }

    @Test("normalization verifier rejects output that is not normalized")
    func normalizationVerificationChecksTheRule() async throws {
        let runtime = SkillRuntime()
        #expect(try await runtime.verify(
            id: SkillRuntime.normalizationManifest.id,
            outputJSON: #"{"text":"  hello  "}"#
        ) == false)
        #expect(try await runtime.verify(
            id: SkillRuntime.normalizationManifest.id,
            outputJSON: #"{"text":"hello"}"#
        ))
    }

}


private actor DeferredSkillOutput {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var outputWaiter: CheckedContinuation<String, Never>?

    func waitForOutput() async -> String {
        await withCheckedContinuation { continuation in
            outputWaiter = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func resume(_ output: String) {
        outputWaiter?.resume(returning: output)
        outputWaiter = nil
    }
}

private struct DeferredExecutor: SkillExecutor {
    let gate: DeferredSkillOutput
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        await gate.waitForOutput()
    }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool { true }
}
