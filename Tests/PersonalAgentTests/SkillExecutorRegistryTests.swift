import Foundation
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
    struct ReadOnlyPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            intent.capabilities == .read
                ? .allow("read-only grant")
                : .deny("execute capability not granted")
        }
    }

    @Test("a Skill manifest cannot downgrade the execution capability")
    func manifestCannotDowngradeExecutionCapability() async throws {
        let id = SkillID(rawValue: "custom.read-only")
        let manifest = SkillManifest(
            id: id, name: "Read-only claim", description: "Attempts to execute with read-only requirements.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "This must not bypass execution authorization.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(EchoExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            executors: registry
        )

        await #expect(throws: SkillRuntimeError.policyDenied("execute capability not granted")) {
            try await runtime.execute(
                id: id,
                inputJSON: #"{ "value": "input" }"#,
                policy: ReadOnlyPolicy()
            )
        }
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

    @Test("An unlisted Skill cannot bind itself to a registered Module")
    func unlistedModuleBackedSkillFailsClosed() async throws {
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
        await #expect(throws: SkillRuntimeError.unknownSkill(id)) {
            try await runtime.execute(
                id: id,
                inputJSON: "{\"text\":\"hello\"}",
                policy: AllowPolicy()
            )
        }
        #expect(try await runtime.verify(id: id, outputJSON: "{\"text\":\"hello\"}") == false)
    }

    @Test("Declared text.normalize executor runs and verifies for an imported Skill ID")
    func declaredTextNormalizeExecutorRunsForImportedSkillID() async throws {
        let id = SkillID(rawValue: "custom.normalize")
        let manifest = SkillManifest(
            id: id,
            name: "Normalize Imported Text",
            description: "Uses the explicitly declared built-in text normalizer.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Trim surrounding whitespace.",
            inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
            outputSchema: SchemaDocument(identifier: "skill.text.normalize.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["executor": "text.normalize"]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        #expect(await runtime.executorAvailability(for: id) == .available)
        let output = try await runtime.executeVerified(
            id: id,
            inputJSON: #"{ "text": "  hello  " }"#,
            policy: AllowPolicy()
        )
        let outputObject = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        #expect(outputObject?["text"] == "hello")
        #expect(try await runtime.verify(id: id, outputJSON: output))
    }

    @Test("Registered per-Skill executor takes precedence over metadata aliases")
    func registeredExecutorTakesPrecedenceOverMetadataAlias() async throws {
        let id = SkillID(rawValue: "custom.normalize-override")
        let manifest = SkillManifest(
            id: id,
            name: "Host Registered Executor",
            description: "A host-registered executor must take precedence.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Use the explicit host registration.",
            inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
            outputSchema: SchemaDocument(identifier: "skill.text.normalize.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["executor": "text.normalize"]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(EchoExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)
        let output = try await runtime.execute(
            id: id,
            inputJSON: #"{ "text": "hello" }"#,
            policy: AllowPolicy()
        )
        let outputObject = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        #expect(outputObject?["value"] == "custom")
    }

    @Test("Unknown executor metadata does not instantiate arbitrary code")
    func unknownExecutorMetadataFailsClosed() async throws {
        let id = SkillID(rawValue: "custom.unknown-executor")
        let manifest = SkillManifest(
            id: id,
            name: "Unknown Executor",
            description: "Declares an executor the host does not support.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Must remain unavailable.",
            inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
            outputSchema: SchemaDocument(identifier: "skill.text.normalize.out"),
            requiredCapabilities: [.read, .execute],
            metadata: ["executor": "shell.execute"]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        #expect(await runtime.executorAvailability(for: id) == .unavailable)
        await #expect(throws: SkillRuntimeError.unknownSkill(id)) {
            _ = try await runtime.execute(
                id: id,
                inputJSON: #"{ "text": "  must not run  " }"#,
                policy: AllowPolicy()
            )
        }
    }

    @Test("Declared text.normalize alias requires the exact built-in schema contract")
    func declaredTextNormalizeAliasRejectsSchemaMismatch() async throws {
        let id = SkillID(rawValue: "custom.normalize-invalid-schema")
        let manifest = SkillManifest(
            id: id,
            name: "Invalid Normalizer Alias",
            description: "Attempts to alias a normalizer with a different output contract.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Must remain unavailable.",
            inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
            outputSchema: SchemaDocument(identifier: "custom.output"),
            requiredCapabilities: [.read, .execute],
            metadata: ["executor": "text.normalize"]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        #expect(await runtime.executorAvailability(for: id) == .unavailable)
        await #expect(throws: SkillRuntimeError.unknownSkill(id)) {
            _ = try await runtime.execute(
                id: id,
                inputJSON: #"{ "text": "hello" }"#,
                policy: AllowPolicy()
            )
        }
    }

    @Test("An unmapped module Skill is rejected before trusting its schema claims")
    func unmappedModuleSkillRejectsSchemaClaims() async throws {
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

        await #expect(throws: SkillRuntimeError.unknownSkill(id)) {
            try await runtime.execute(
                id: id,
                inputJSON: #"{"text":"hello"}"#,
                policy: AllowPolicy()
            )
        }
        #expect(try await runtime.verify(id: id, outputJSON: #"{"text":"hello"}"#) == false)
    }

    @Test("direct verified execution rejects executor output that fails verification")
    func directExecutionRejectsUnverifiedOutput() async throws {
        let id = SkillID(rawValue: "custom.unverified")
        let manifest = SkillManifest(
            id: id,
            name: "Unverified Output",
            description: "Executor output must pass its verifier.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return a result that the verifier rejects.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read, .execute]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(RejectingVerifierExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)
        await #expect(throws: SkillRuntimeError.verificationFailed(id)) {
            _ = try await runtime.executeVerified(
                id: id,
                inputJSON: #"{"value":"request"}"#,
                policy: AllowPolicy()
            )
        }
    }


    @Test("verified execution rejects output that violates the manifest schema even when executor accepts it")
    func verifiedExecutionRejectsOutputOutsideManifestSchema() async throws {
        let id = SkillID(rawValue: "custom.invalid-schema-output")
        let manifest = SkillManifest(
            id: id,
            name: "Invalid schema output",
            description: "The executor accepts output that violates the declared output schema.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return an object that violates the output schema.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(
                identifier: "out",
                rawJSON: #"{"type":"object","properties":{"value":{"type":"string"}},"required":["value"],"additionalProperties":false}"#
            ),
            requiredCapabilities: [.read, .execute]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(AcceptingInvalidSchemaExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        await #expect(throws: SkillRuntimeError.verificationFailed(id)) {
            _ = try await runtime.executeVerified(
                id: id,
                inputJSON: #"{"request":"hello"}"#,
                policy: AllowPolicy()
            )
        }
    }

    @Test("standalone verify rejects schema-invalid output even when executor accepts it")
    func standaloneVerifyRejectsOutputOutsideManifestSchema() async throws {
        let id = SkillID(rawValue: "custom.invalid-schema-output")
        let manifest = SkillManifest(
            id: id,
            name: "Invalid schema output",
            description: "The executor accepts output that violates the declared output schema.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return an object that violates the output schema.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(
                identifier: "out",
                rawJSON: #"{ "type": "object", "properties": { "value": { "type": "string" } }, "required": ["value"], "additionalProperties": false }"#
            ),
            requiredCapabilities: [.read, .execute]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(AcceptingInvalidSchemaExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        #expect(try await runtime.verify(id: id, outputJSON: #"{}"#) == false)
        #expect(try await runtime.verify(id: id, outputJSON: #"{ "value": "valid", "unexpected": true }"#) == false)
        #expect(try await runtime.verify(id: id, outputJSON: #"{ "value": "valid" }"#) == true)
    }

    @Test("unscoped Skill Agent rejects execution before selecting an executor")
    func unscopedSkillAgentRejectsExecution() async throws {
        let id = SkillID(rawValue: "custom.agent-unverified")
        let manifest = SkillManifest(
            id: id,
            name: "Agent Unverified Output",
            description: "Agent output must pass its executor verifier.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return output that fails verification.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read, .execute]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(RejectingVerifierExecutor(), for: id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)
        let orchestrator = SkillAgentOrchestrator(runtime: runtime)

        await #expect(throws: SkillAgentOrchestratorError.agentScopeRequired) {
            _ = try await orchestrator.run(
                goalStatement: id.rawValue,
                inputJSON: #"{"value":"request"}"#,
                policy: AllowPolicy()
            )
        }
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


private struct AcceptingInvalidSchemaExecutor: SkillExecutor {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        #"{"unexpected":true}"#
    }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        true
    }
}

private struct RejectingVerifierExecutor: SkillExecutor {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        #"{"value":"untrusted"}"#
    }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool { false }
}
