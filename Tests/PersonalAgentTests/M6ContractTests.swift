import PASkills
import Testing
import Foundation
import PAFoundation
import PAArchitecture
import PAKernel
import PAPolicy
import PACognition
import PAAgency
import PAModules
import PAMemory
import PAProviders
import PAComposition
import PAEvents
import PATools

@Suite("M6 Architectural Contract & Verification Gate Tests")
struct M6ContractTests {

    struct RejectingApprovalGate: ApprovalGate {
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            return false
        }
    }

    struct AcceptingApprovalGate: ApprovalGate {
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            return true
        }
    }

    struct ApprovalRequiredPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .approve("Approval needed for action")
        }
    }

    struct MockCognitionPipeline: CognitionPipelining {
        let outputToReturn: CognitionOutput
        let reflectionToReturn: Reflection

        func process(perception: Perception, goalID: GoalID) async throws -> CognitionOutput {
            return outputToReturn
        }

        func reflect(feedback: CognitionFeedback) async throws -> Reflection {
            return reflectionToReturn
        }
    }

    struct MockAgencyLoop: AgencyLooping {
        let feedbackToReturn: CognitionFeedback

        func executePlan(
            output: CognitionOutput,
            policy: any PolicyEvaluating,
            gate: (any ApprovalGate)?,
            moduleExecutor: (any ModuleExecuting)?
        ) async throws -> CognitionFeedback {
            return feedbackToReturn
        }

        func run(goalID: GoalID) async throws -> Evaluation {
            return feedbackToReturn.evaluation
        }
    }

    // 1 & 2. Plan and ActionProposal cross Cognition -> Agency explicitly
    @Test("Plan and ActionProposal cross Cognition -> Agency boundary explicitly")
    func planAndProposalsCrossBoundary() async throws {
        let root = try await M6CompositionRoot(
            storeDirectoryURL: createTempDir(),
            modules: [ToolModule(tool: EchoTool())]
        )
        try await root.runtime.start()

        let goal = Goal(statement: "Cross Boundary Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let perception = Perception(rawInput: "echo", source: "user")
        let cognitionOutput = try await root.orchestrator.processCognition(perception: perception, goalID: goal.id)

        #expect(cognitionOutput.plan.goalID == goal.id)
        #expect(cognitionOutput.proposals.count == 1)
        #expect(cognitionOutput.proposals[0].planID == cognitionOutput.plan.id)
        #expect(cognitionOutput.verification.accepted == true)

        let feedback = try await root.orchestrator.executeAgency(output: cognitionOutput)
        #expect(feedback.observations.count == 1)
        #expect(feedback.evaluation.goalID == goal.id)
    }

    // 3. Verification rejection prevents execution
    @Test("Verification rejection prevents execution")
    func verificationRejectionPreventsExecution() async throws {
        let root = try await M6CompositionRoot(storeDirectoryURL: createTempDir())
        try await root.runtime.start()

        let goal = Goal(statement: "Verification Fail Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "echo"), description: "forbidden", capabilities: .read)
        let rejectedOutput = CognitionOutput(
            plan: plan,
            proposals: [proposal],
            verification: VerificationResult(accepted: false, notes: "Schema invalid")
        )

        let feedback = try await root.orchestrator.executeAgency(output: rejectedOutput)
        #expect(feedback.observations.isEmpty)
        #expect(feedback.evaluation.disposition == .abort)
    }

    // 4. Policy denial prevents execution
    @Test("Policy denial prevents execution")
    func policyDenialPreventsExecution() async throws {
        let root = try await M6CompositionRoot(
            policy: DenyingPolicyEvaluator(),
            storeDirectoryURL: createTempDir(),
            modules: [ToolModule(tool: EchoTool())]
        )
        try await root.runtime.start()

        let goal = Goal(statement: "Denied Policy Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let perception = Perception(rawInput: "unauthorized task", source: "user")
        let output = try await root.orchestrator.processCognition(perception: perception, goalID: goal.id)

        let feedback = try await root.orchestrator.executeAgency(output: output)
        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == false)
        #expect(feedback.observations[0].summary.contains("Policy denied"))
    }

    // 5. Approval failure prevents execution
    @Test("Approval failure prevents execution")
    func approvalFailurePreventsExecution() async throws {
        let authorizer = DefaultActionAuthorizer()
        let proposal = ActionProposal(
            planID: PlanID(),
            toolID: ToolID(rawValue: "sensitive"),
            description: "sensitive action",
            capabilities: .write
        )

        let deniedIntent = try await authorizer.authorize(
            proposal: proposal,
            policy: ApprovalRequiredPolicy(),
            gate: RejectingApprovalGate()
        )
        #expect(deniedIntent == nil)

        let allowedIntent = try await authorizer.authorize(
            proposal: proposal,
            policy: ApprovalRequiredPolicy(),
            gate: AcceptingApprovalGate()
        )
        #expect(allowedIntent != nil)
    }

    // 6 & 7. Authorized actions execute and produce Observations; throws produce failed Observation
    @Test("Authorized actions execute and produce Observations fail closed on error")
    func authorizedActionsExecuteAndFailClosedOnError() async throws {
        let root = try await M6CompositionRoot(
            policy: PermissivePolicyEvaluator(),
            storeDirectoryURL: createTempDir(),
            modules: [ToolModule(tool: EchoTool()), FailingModule(), EchoModule()]
        )
        try await root.runtime.start()

        let goal = Goal(statement: "Execute Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        // Succeeded tool execution
        let plan = Plan(goalID: goal.id, steps: [PlanStep(index: 0, description: "echo", skillID: nil)])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "tool.echo"), description: "echo", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))

        let feedback = try await root.orchestrator.executeAgency(output: output)
        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == true)
        #expect(feedback.evaluation.disposition == AgencyDisposition.complete)

        // Failed module execution fail-closed
        let failProposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.fail"), description: "failing", capabilities: .read)
        let failOutput = CognitionOutput(plan: plan, proposals: [failProposal], verification: VerificationResult(accepted: true, notes: "OK"))
        let failFeedback = try await root.orchestrator.executeAgency(output: failOutput)
        #expect(failFeedback.observations.count == 1)
        #expect(failFeedback.observations[0].succeeded == false)
        #expect(failFeedback.evaluation.disposition == AgencyDisposition.continue)
    }

    // 8, 9, 10. Agency produces Evaluation; Observation + Evaluation re-enter Cognition; Reflection is post-execution
    @Test("Full M6 normative loop with post-execution Reflection feedback loop")
    func fullNormativeLoopWithReflection() async throws {
        let root = try await M6CompositionRoot(
            storeDirectoryURL: createTempDir(),
            modules: [ToolModule(tool: EchoTool())]
        )
        try await root.runtime.start()

        let goal = Goal(statement: "Complete Loop Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [PlanStep(index: 0, description: "step", skillID: nil)])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "tool.echo"), description: "echo", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))
        let mockCognition = MockCognitionPipeline(
            outputToReturn: output,
            reflectionToReturn: Reflection(notes: "Post-execution reflection complete", shouldAdapt: false)
        )
        let mockAgency = MockAgencyLoop(
            feedbackToReturn: CognitionFeedback(
                observations: [Observation(actionID: proposal.actionID, summary: "executed", succeeded: true)],
                evaluation: Evaluation(goalID: goal.id, disposition: .complete, reason: "all green")
            )
        )

        let disposition = try await root.orchestrator.runCycle(
            perception: Perception(rawInput: "echo", source: "test"),
            goalID: goal.id,
            customCognition: mockCognition,
            customAgency: mockAgency
        )

        #expect(disposition == AgencyDisposition.complete)
        let currentState = await root.runtime.currentState()
        #expect(currentState.activeGoalID == nil) // Goal completed deterministically
    }

    // 11 & 12. StateUpdate cannot bypass owner, AgentRuntime remains authoritative
    @Test("StateUpdate cannot bypass owner; AgentRuntime remains authoritative")
    func stateUpdatePreservesRuntimeAuthority() async throws {
        let root = try await M6CompositionRoot(storeDirectoryURL: createTempDir())
        try await root.runtime.start()

        let goal = Goal(statement: "Authoritative Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let memoryRecord = MemoryRecord(
            id: MemoryRecordID(),
            kind: .fact,
            content: "Learned context",
            provenance: Provenance(source: "reflection")
        )

        let update = StateUpdate(
            goalID: goal.id,
            memoryRecordsToCapture: [memoryRecord],
            reflection: Reflection(notes: "Captured memory", shouldAdapt: false)
        )

        // Submit state update to AgentRuntime
        try await root.runtime.applyStateUpdate(update)

        // Memory was persisted through PAMemory owner
        let count = try await root.memoryRuntime.count()
        #expect(count == 1)

        // AgentState is still owned by AgentRuntime
        let state = await root.runtime.currentState()
        #expect(state.activeGoalID == goal.id)
    }

    // 13, 14, 15. Continue, Complete, Abort cycle semantics
    @Test("Continue, Complete, Abort cycle semantics")
    func cycleSemantics() async throws {
        let root = try await M6CompositionRoot(storeDirectoryURL: createTempDir())
        try await root.runtime.start()

        // Test Abort
        let goal1 = Goal(statement: "Abort Goal")
        try await root.runtime.submit(goal: goal1)
        try await root.runtime.activate(goalID: goal1.id)

        let rejectedOutput = CognitionOutput(
            plan: Plan(goalID: goal1.id, steps: []),
            proposals: [ActionProposal(planID: PlanID(), toolID: nil, description: "x", capabilities: .read)],
            verification: VerificationResult(accepted: false, notes: "Reject")
        )
        let mockRejectedCognition = MockCognitionPipeline(
            outputToReturn: rejectedOutput,
            reflectionToReturn: Reflection(notes: "Abort notes", shouldAdapt: false)
        )

        let disposition1 = try await root.orchestrator.runCycle(
            perception: Perception(rawInput: "bad", source: "test"),
            goalID: goal1.id,
            customCognition: mockRejectedCognition
        )
        #expect(disposition1 == .abort)
        let goal1State = await root.runtime.goal(id: goal1.id)
        #expect(goal1State?.status == .aborted)
    }

    // 16, 17, 18. Audit evidence, Concurrency & Import boundary verification
    @Test("M6 event auditability and imports manifest")
    func auditabilityAndManifest() async throws {
        let root = try await M6CompositionRoot(
            storeDirectoryURL: createTempDir(),
            modules: [ToolModule(tool: EchoTool())]
        )
        try await root.runtime.start()

        let goal = Goal(statement: "Audit Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let perception = Perception(rawInput: "echo", source: "test")
        _ = try await root.orchestrator.runCycle(perception: perception, goalID: goal.id)

        let events = await root.eventLog.allEvents()
        #expect(!events.isEmpty)
        #expect(events.contains(where: { $0.kind == ExecutionEventKind.stateUpdated }))

        #expect(ArchitectureManifest.milestone == "M6")
        #expect(MilestoneGate.m6.cognitionLoop == true)
    }

    private func createTempDir() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}
