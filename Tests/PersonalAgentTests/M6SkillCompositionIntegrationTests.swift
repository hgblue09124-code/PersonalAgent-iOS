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
}
