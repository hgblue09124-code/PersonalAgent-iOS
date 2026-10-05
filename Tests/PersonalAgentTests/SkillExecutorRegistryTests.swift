import Testing
import PAKernel
import PARuntime
import PASkills

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
}