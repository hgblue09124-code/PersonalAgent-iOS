import Foundation
import Testing
import PAKernel
import PARuntime
import PASkills

@Suite("Personal Agent Theory Execution Proof")
struct PersonalAgentTheoryExecutionProofTests {
    struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .allow("proof test")
        }
    }

    @Test("Skill.md rule executes inside Agent.md scope and produces verified evidence")
    func markdownToVerifiedExecution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-theory-proof-\(UUID().uuidString)", isDirectory: true)
        let skillsDirectory = root.appendingPathComponent("Skills", isDirectory: true)
        let agentsDirectory = root.appendingPathComponent("Agents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)

        let skillMarkdown = """
        id: text.normalize
        name: Text Normalize
        version: 1.0.0
        description: Normalize text by trimming surrounding whitespace.
        ---
        ## Input
        skill.text.normalize.in

        ## Output
        skill.text.normalize.out

        ## Rule
        Trim surrounding whitespace.
        """
        let agentMarkdown = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Agent constrained to the declared skill.
        ---
        ## Skills
        text.normalize

        ## Rule
        Select only a declared skill for the requested goal.
        """

        try skillMarkdown.write(to: skillsDirectory.appendingPathComponent("text.normalize.Skill.md"), atomically: true, encoding: .utf8)
        try agentMarkdown.write(to: agentsDirectory.appendingPathComponent("personal.default.Agent.md"), atomically: true, encoding: .utf8)

        let skillStore = FileSkillStore(directoryURL: skillsDirectory)
        let agentStore = FileAgentStore(directoryURL: agentsDirectory)
        let skill = try await skillStore.load(id: SkillID(rawValue: "text.normalize"))
        let agent = try await agentStore.load(id: "personal.default")

        #expect(skill.instructions == "Trim surrounding whitespace.")
        #expect(agent.skillIDs.map(\.rawValue) == ["text.normalize"])

        let runtime = SkillRuntime(store: skillStore)
        let orchestrator = SkillAgentOrchestrator(runtime: runtime)
        let result = try await orchestrator.run(
            agent: agent,
            goalStatement: "normalize text",
            inputJSON: "{\"text\":\"  theory works  \"}",
            policy: AllowPolicy()
        )

        #expect(result.skillID == SkillID(rawValue: "text.normalize"))
        #expect(result.outputJSON == "{\"text\":\"theory works\"}")
        #expect(result.verified)
    }
}
