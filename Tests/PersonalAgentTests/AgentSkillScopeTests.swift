import Testing
import PAKernel
import PARuntime
import PASkills

@Suite("Agent Skill Scope")
struct AgentSkillScopeTests {
    struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("allowed") }
    }

    @Test("agent selection is restricted to declared skills")
    func scopesSelection() async throws {
        let normalize = SkillRuntime.normalizationManifest
        let other = SkillManifest(
            id: SkillID(rawValue: "text.other"),
            name: "Other Text",
            description: "Other text operation.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return other text.",
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out"),
            requiredCapabilities: [.read, .execute]
        )
        let store = InMemorySkillStore(manifests: [normalize, other])
        let registry = SkillExecutorRegistry(executors: [normalize.id.rawValue: TextNormalizeSkillExecutor()])
        let runtime = SkillRuntime(store: store, executors: registry)
        let orchestrator = SkillAgentOrchestrator(runtime: runtime)
        let agent = AgentManifest(
            id: "normalize-only",
            name: "Normalize Agent",
            description: "Only normalizes text.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            skillIDs: [normalize.id],
            instructions: "Use only the declared skill."
        )

        let result = try await orchestrator.run(
            agent: agent,
            goalStatement: "normalize this text",
            inputJSON: "{\"text\":\"  hello  \"}",
            policy: AllowPolicy()
        )
        #expect(result.skillID == normalize.id)
        #expect(result.verified)
    }

    @Test("agent scope with no matching declared skill fails closed")
    func rejectsOutOfScopeSelection() async {
        let agent = AgentManifest(
            id: "other-only",
            name: "Other Only",
            description: "No normalize skill.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            skillIDs: [SkillID(rawValue: "text.other")],
            instructions: "Only text.other."
        )
        let runtime = SkillRuntime()
        let orchestrator = SkillAgentOrchestrator(runtime: runtime)

        await #expect(throws: SkillRuntimeError.noSelection) {
            try await orchestrator.run(
                agent: agent,
                goalStatement: "normalize this text",
                inputJSON: "{\"text\":\" hello \"}",
                policy: AllowPolicy()
            )
        }
    }
}
