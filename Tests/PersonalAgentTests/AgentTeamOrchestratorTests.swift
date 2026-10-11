import Testing
import PAKernel
import PASkills

@Suite("Agent Team Orchestration")
struct AgentTeamOrchestratorTests {
    struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("allowed") }
    }

    private func agent(_ id: String) -> AgentManifest {
        AgentManifest(
            id: id,
            name: "Agent \(id)",
            description: "Normalizes text.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            skillIDs: [SkillRuntime.normalizationManifest.id],
            instructions: "Use the declared normalization Skill."
        )
    }

    private func makeOrchestrator() -> AgentTeamOrchestrator {
        let manifest = SkillRuntime.normalizationManifest
        let store = InMemorySkillStore(manifests: [manifest])
        let registry = SkillExecutorRegistry(executors: [
            manifest.id.rawValue: TextNormalizeSkillExecutor()
        ])
        let runtime = SkillRuntime(store: store, executors: registry)
        return AgentTeamOrchestrator(skillOrchestrator: SkillAgentOrchestrator(runtime: runtime))
    }

    @Test("runs all matching agents in stable order and verifies each result")
    func runsMatchingAgents() async throws {
        let team = makeOrchestrator()
        let result = try await team.run(
            agents: [agent("z-agent"), agent("a-agent")],
            goalStatement: "normalize this text",
            inputJSON: #"{"text":"  hello  "}"#,
            policy: AllowPolicy()
        )
        #expect(result.members.map(\.agentID) == ["a-agent", "z-agent"])
        #expect(result.members.allSatisfy { $0.skillResult.verified })
        #expect(result.members.allSatisfy { $0.skillResult.skillID == SkillRuntime.normalizationManifest.id })
    }

    @Test("returns no matching skills rather than inventing a result")
    func failsWhenNoSkillMatches() async {
        let team = makeOrchestrator()
        await #expect(throws: AgentTeamOrchestratorError.noMatchingSkills) {
            try await team.run(
                agents: [agent("normalize-only")],
                goalStatement: "calculate a rocket trajectory",
                inputJSON: #"{"text":"calculate a rocket trajectory"}"#,
                policy: AllowPolicy()
            )
        }
    }

    @Test("empty agent roster fails closed")
    func rejectsEmptyRoster() async {
        let team = makeOrchestrator()
        await #expect(throws: AgentTeamOrchestratorError.noAgents) {
            try await team.run(
                agents: [],
                goalStatement: "normalize this text",
                inputJSON: #"{"text":"hello"}"#,
                policy: AllowPolicy()
            )
        }
    }
}
