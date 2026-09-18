import Testing
import Foundation
import PAFoundation
import PAKernel
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PAComposition

@Suite("M7 Runtime Tests")
struct M7RuntimeTests {

    @Test("Run creation and persistence in RunStore")
    func testRunCreationAndPersistence() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Test M7 Run")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        #expect(record.goalID == goal.id)
        #expect(record.status == .running)

        let storedRecord = try await composition.runStore.record(for: record.runID)
        #expect(storedRecord != nil)
        #expect(storedRecord?.runID == record.runID)
        #expect(storedRecord?.status == .running)
    }

    @Test("Cycle execution produces pre-execution and post-execution checkpoints")
    func testCheckpointsProducedInCycle() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Run durable cycle")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID, maxStepCount: 10)

        let eval = try await composition.lifecycleManager.runCycle(runID: record.runID, lease: lease)
        #expect(eval.goalID == goal.id)

        let checkpoints = try await composition.checkpointStore.checkpoints(for: record.runID)
        #expect(checkpoints.count >= 2)
    }

    @Test("Policy denial records failed attempt and observation")
    func testPolicyDenialRecordsFailedAttempt() async throws {
        struct DenyAllPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                .deny("Policy forbidden")
            }
        }

        let composition = try await M7CompositionRoot(policy: DenyAllPolicy())
        let goal = Goal(statement: "Forbidden action")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID, maxStepCount: 10)

        let eval = try await composition.lifecycleManager.runCycle(runID: record.runID, lease: lease)
        #expect(eval.disposition == .abort)

        let attempts = try await composition.attemptStore.attempts(for: record.runID)
        #expect(!attempts.isEmpty)
        #expect(attempts.allSatisfy { $0.status == .failed })
    }

    @Test("AgentRuntime remains sole authority over AgentState and GoalStatus")
    func testAgentRuntimeSoleAuthority() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Check state authority")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID, maxStepCount: 10)

        _ = try await composition.lifecycleManager.runCycle(runID: record.runID, lease: lease)

        let agentState = await composition.runtime.currentState()
        let runtimeGoal = await composition.runtime.goal(id: goal.id)
        let runRecord = try await composition.runStore.record(for: record.runID)

        #expect(agentState.identity.displayName == "Personal M7")
        #expect(runtimeGoal != nil)
        #expect(runRecord != nil)
        #expect(runtimeGoal?.status.rawValue == runRecord?.status.rawValue || runRecord?.status == .completed || runRecord?.status == .failed)
    }
}
