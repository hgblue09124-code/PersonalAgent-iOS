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

    @Test("M8 chat does not expose workspace Skill when workspace tools are disabled")
    func m8WorkspaceSkillRemainsOutOfScopeWhenDisabled() async throws {
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

        let result = try await root.runChatSkillIfMatched(
            goalStatement: "Tạo file workspace/blocked.md với nội dung: must not be written"
        )
        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/blocked.md").path))

        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.create-file"
        }
        #expect(observation == nil)
    }
}
