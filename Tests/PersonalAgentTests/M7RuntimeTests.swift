import Testing
import Foundation
import PAFoundation
import PAKernel
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PATools
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
        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(targetCapabilities: [cap], tools: [tool])
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

    @Test("Approval Gate fail closed: decision requires approval but gate is nil fails closed")
    func testApprovalRequiredWithoutGateFailsClosed() async throws {
        struct ApprovalRequiredPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                PolicyDecision(allowed: true, requiresApproval: true, reason: "Sensitive action")
            }
        }

        let composition = try await M7CompositionRoot(policy: ApprovalRequiredPolicy(), approvalGate: nil)
        let goal = Goal(statement: "Action requiring approval")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID, maxStepCount: 10)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: ToolID(rawValue: "echo"),
            description: "sensitive action",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .failed)
        #expect(obs.summary.contains("Denied by policy"))
    }

    @Test("Approval Gate enforces approval decision when gate exists")
    func testApprovalGateEnforcement() async throws {
        struct ApprovalRequiredPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                PolicyDecision(allowed: false, requiresApproval: true, reason: "Sensitive action")
            }
        }

        struct DenyingApprovalGate: ApprovalGate {
            func requestApproval(for intent: ActionIntent) async throws -> Bool { false }
        }

        struct GrantingApprovalGate: ApprovalGate {
            func requestApproval(for intent: ActionIntent) async throws -> Bool { true }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)

        // Test Denied Gate
        let deniedComp = try await M7CompositionRoot(
            policy: ApprovalRequiredPolicy(),
            approvalGate: DenyingApprovalGate(),
            targetCapabilities: [cap],
            tools: [tool]
        )
        let goal1 = Goal(statement: "Denied approval")
        try await deniedComp.runtime.submit(goal: goal1)
        let rec1 = try await deniedComp.lifecycleManager.createRun(goalID: goal1.id)
        let lease1 = CapabilityLease(runID: rec1.runID)
        let prop1 = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )
        let (obs1, att1) = try await deniedComp.executionBoundary.executeProposal(
            proposal: prop1,
            runID: rec1.runID,
            goalID: goal1.id,
            traceID: rec1.traceID,
            cycleIndex: 1,
            lease: lease1
        )
        #expect(!obs1.succeeded)
        #expect(att1.status == .failed)

        // Test Granted Gate
        let grantedComp = try await M7CompositionRoot(
            policy: ApprovalRequiredPolicy(),
            approvalGate: GrantingApprovalGate(),
            targetCapabilities: [cap],
            tools: [tool]
        )
        let goal2 = Goal(statement: "Granted approval")
        try await grantedComp.runtime.submit(goal: goal2)
        let rec2 = try await grantedComp.lifecycleManager.createRun(goalID: goal2.id)
        let lease2 = CapabilityLease(runID: rec2.runID)
        let prop2 = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )
        let (obs2, att2) = try await grantedComp.executionBoundary.executeProposal(
            proposal: prop2,
            runID: rec2.runID,
            goalID: goal2.id,
            traceID: rec2.traceID,
            cycleIndex: 1,
            lease: lease2
        )
        #expect(obs2.succeeded)
        #expect(att2.status == .completed)
    }

    @Test("Target throw during dispatch leaves attempt status as STARTED_UNKNOWN")
    func testTargetThrowLeavesStatusStartedUnknown() async throws {
        struct ThrowingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "throwingTool"),
                name: "Throwing",
                version: SemanticVersion(major: 0, minor: 1, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.throw.in"),
                outputSchema: SchemaDocument(identifier: "tool.throw.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct TargetError: Error {}
                throw TargetError()
            }
        }

        let tool = ThrowingTool()
        let composition = try await M7CompositionRoot(tools: [tool])
        let goal = Goal(statement: "Throwing target test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "throw test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)

        let storedAttempt = try await composition.attemptStore.attempt(for: attempt.attemptID)
        #expect(storedAttempt?.status == .startedUnknown)
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
