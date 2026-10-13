import Foundation
import Testing
import PAKernel
import PARuntime
import PAEvents
import PASkills
import PAComposition

@Suite("Canonical M6 Skill Composition")
struct M6SkillCompositionIntegrationTests {
    private struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("integration test grant") }
    }

    @Test("registered Skill executes and verifies through canonical composition")
    func executesVerifiedSkill() async throws {
        let manifest = SkillRuntime.normalizationManifest
        let root = try await M6CompositionRoot(
            policy: AllowPolicy(),
            skillStore: InMemorySkillStore(manifests: [manifest]),
            skillExecutors: SkillExecutorRegistry(executors: [
                manifest.id.rawValue: TextNormalizeSkillExecutor()
            ]),
            allowedSkillIDs: [manifest.id]
        )
        let goal = Goal(statement: manifest.id.rawValue)
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)
        let events = try await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == manifest.id.rawValue
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 canonical chat loop executes and verifies a declared Skill")
    func m8CanonicalLoopExecutesSkill() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let goal = Goal(statement: "text.normalize")
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)
        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "text.normalize"
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 workspace Skill creates and verifies a real file")
    func m8WorkspaceSkillCreatesVerifiedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let content = "Skill wrote this file."
        let goal = Goal(statement: "Tạo file workspace/notes.md với nội dung: \(content)")
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)

        let fileURL = directory.appendingPathComponent("workspace/notes.md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)

        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.create-file"
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 workspace search finds a real matching file through the Skill loop")
    func m8WorkspaceSearchFindsMatchingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "A unique needle appears here.".write(
            to: workspace.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )

        let skills = try await root.discoverSkills()
        #expect(skills.contains { $0.id.rawValue == "workspace.search" })
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.contains { $0.rawValue == "workspace.search" })

        let result = try await root.runChatSkillIfMatched(goalStatement: "Tìm kiếm workspace needle")
        #expect(result?.skillID.rawValue == "workspace.search")
        #expect(result?.verified == true)
        #expect(result?.outputJSON.contains("workspace/notes.md") == true)

        let englishResult = try await root.runChatSkillIfMatched(
            goalStatement: "Search workspace for needle"
        )
        #expect(englishResult?.skillID.rawValue == "workspace.search")
        #expect(englishResult?.verified == true)
        #expect(englishResult?.outputJSON.contains("workspace/notes.md") == true)

        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.search"
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 chat does not expose workspace Skills when workspace tools are disabled")
    func m8WorkspaceSkillsRemainOutOfScopeWhenDisabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )

        let createResult = try await root.runChatSkillIfMatched(
            goalStatement: "Tạo file workspace/blocked.md với nội dung: must not be written"
        )
        let searchResult = try await root.runChatSkillIfMatched(
            goalStatement: "Tìm kiếm workspace secretneedle"
        )
        let teamSearchResult = try await root.runChatTeamIfMatched(
            goalStatement: "Search workspace for secretneedle"
        )
        #expect(createResult == nil)
        #expect(searchResult == nil)
        #expect(teamSearchResult == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/blocked.md").path))

        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.read"
        })
        #expect(!events.contains {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.search"
        })
    }

    @Test("Workspace Skills stay out of scope after agent-specific selection")
    func workspaceSkillsCannotLeakThroughCustomAgentScopeWhenDisabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skills = directory.appendingPathComponent("Skills", isDirectory: true)
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let unrelatedSkill = """
        id: workspace.query
        name: Workspace Query
        version: 1.0.0
        description: A helper for workspace search queries.
        ---
        ## Input
        workspace.query.input

        ## Output
        workspace.query.output

        ## Rule
        Describe a workspace query.
        """
        try unrelatedSkill.write(
            to: skills.appendingPathComponent("workspace.query.Skill.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspaceOnlyAgent = """
        id: personal.workspace-only
        name: Workspace-only Agent
        version: 1.0.0
        description: Only the workspace search Skill is allowed.
        ---
        ## Skills
        workspace.search

        ## Rule
        Search workspace content only when the workspace capability is enabled.
        """
        try workspaceOnlyAgent.write(
            to: agents.appendingPathComponent("personal.workspace-only.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )

        let direct = try await root.runChatSkillIfMatched(
            goalStatement: "Workspace Query search",
            agentID: "personal.workspace-only"
        )
        let team = try await root.runChatTeamIfMatched(goalStatement: "Workspace Query search")
        #expect(direct == nil)
        #expect(team == nil)

        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.read"
        })
    }

    @Test("Default Agent migrates only the exact previous built-in scope")
    func defaultAgentMigratesPreviousBuiltInScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let previousDefault = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent.
        ---
        ## Skills
        text.normalize
        workspace.create-file

        ## Rule
        Select only from the declared skills. Use the workspace.create-file Skill for explicit file creation requests.
        """
        try previousDefault.write(
            to: agents.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.contains { $0.rawValue == "workspace.search" })
    }

    @Test("User-edited Agent scope is preserved during workspace Skill installation")
    func userEditedAgentScopeIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let customAgent = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Custom user scope.
        ---
        ## Skills
        text.normalize

        ## Rule
        Keep the custom scope unchanged.
        """
        try customAgent.write(
            to: agents.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.map(\.rawValue) == ["text.normalize"])
        #expect(agent.instructions == "Keep the custom scope unchanged.")
    }
}
