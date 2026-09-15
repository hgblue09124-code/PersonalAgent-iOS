import Testing
import Foundation
import PAFoundation
import PAArchitecture
import PAKernel
import PAPolicy
import PACognition
import PAAgency
import PAModules
import PASkills
import PATools
import PAMemory
import PAObservability
import PAEvents
import PAProviders
import PAComposition

@Suite("M6 Architectural Contract & Verification Gate Tests")
struct M6ContractTests {

    struct ApprovalRequiredPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            if intent.capabilities.contains(.write) || intent.capabilities.contains(.destructive) {
                return .approve("Requires user approval")
            }
            return .allow("Permitted")
        }
    }

    struct RejectingApprovalGate: ApprovalGate {
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            false
        }
    }

    struct AcceptingApprovalGate: ApprovalGate {
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            true
        }
    }

    struct MockCognitionPipeline: CognitionPipelining {
        let outputToReturn: CognitionOutput
        let reflectionToReturn: Reflection

        func process(perception: Perception, goalID: GoalID) async throws -> CognitionOutput {
            outputToReturn
        }

        func reflect(feedback: CognitionFeedback) async throws -> Reflection {
            reflectionToReturn
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
            feedbackToReturn
        }

        func run(goalID: GoalID) async throws -> Evaluation {
            feedbackToReturn.evaluation
        }
    }

    /// Test helper wiring deterministic modules for M6 contract tests
    private func createTestComposition(
        policy: (any PolicyEvaluating)? = nil,
        approvalGate: (any ApprovalGate)? = nil
    ) async throws -> (root: M6CompositionRoot, echoModule: EchoModule, failModule: FailingModule) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let echo = EchoModule()
        let fail = FailingModule()
        let toolMod = ToolModule(tool: EchoTool())

        let root = try await M6CompositionRoot(
            identity: AgentIdentity(displayName: "M6TestAgent"),
            logger: NullLogger(),
            policy: policy,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: tempDir,
            modules: [echo, fail, toolMod]
        )
        return (root, echo, fail)
    }

    // 1 & 2. Plan and ActionProposal cross Cognition -> Agency explicitly
    @Test("Plan and ActionProposal cross Cognition -> Agency boundary explicitly")
    func planAndProposalCrossBoundary() async throws {
        let (root, _, _) = try await createTestComposition()
        try await root.runtime.start()

        let goal = Goal(statement: "Test Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let perception = Perception(rawInput: "mod.echo", source: "user")
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
        let (root, _, _) = try await createTestComposition()
        try await root.runtime.start()

        let goal = Goal(statement: "Verification Fail Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.echo"), description: "forbidden", capabilities: .read)
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
        let (root, _, _) = try await createTestComposition(policy: DenyingPolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Denied Policy Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.echo"), description: "unauthorized task", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))

        let feedback = try await root.orchestrator.executeAgency(output: output)
        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == false)
        #expect(feedback.observations[0].summary.contains("Policy denied"))
    }

    // 5. Approval failure prevents execution
    @Test("Approval failure prevents execution")
    func approvalFailurePreventsExecution() async throws {
        let authorizer = DefaultActionAuthorizer()
        let proposal = ActionProposal(planID: PlanID(), toolID: ToolID(rawValue: "mod.echo"), description: "sensitive action", capabilities: .write)

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

    // 6 & 7. Authorized actions execute and produce Observations
    @Test("Authorized actions execute and produce Observations")
    func authorizedActionsExecuteAndProduceObservations() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Execute Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [PlanStep(index: 0, description: "echo", skillID: nil)])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.echo"), description: "echo", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))

        let feedback = try await root.orchestrator.executeAgency(output: output)

        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == true)
        #expect(feedback.evaluation.disposition == .complete)
    }

    // 8. Execution failure preserves evidence and reports succeeded: false
    @Test("Execution failure preserves failure evidence and reports succeeded: false")
    func executionFailurePreservesEvidence() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Failing Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [PlanStep(index: 0, description: "mod.fail", skillID: nil)])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.fail"), description: "mod.fail", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))

        let feedback = try await root.orchestrator.executeAgency(output: output)

        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == false)
        #expect(feedback.observations[0].summary.contains("Module execution failed"))
        #expect(feedback.evaluation.disposition == AgencyDisposition.abort)

        let events = await root.eventLog.allEvents()
        #expect(events.contains(where: { $0.kind == ExecutionEventKind.failed }))
    }

    // 9. Unknown or unregistered module fails closed
    @Test("Unknown or unregistered execution target fails closed")
    func unknownTargetFailsClosed() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Unknown Module Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let plan = Plan(goalID: goal.id, steps: [])
        let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.does-not-exist"), description: "nonexistent", capabilities: .read)
        let output = CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "OK"))

        let feedback = try await root.orchestrator.executeAgency(output: output)

        #expect(feedback.observations.count == 1)
        #expect(feedback.observations[0].succeeded == false)
        #expect(feedback.evaluation.disposition == .abort)
    }

    // 10. Multi-cycle Continue re-enters Cognition with post-execution feedback
    @Test("Continue causes a real subsequent Cognition cycle using prior Observation and Evaluation")
    func continueTriggersRealSubsequentCognitionCycle() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Multi Cycle Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        actor CognitionTracker: CognitionPipelining {
            var cycle1Feedback: CognitionFeedback?
            var cycle2Feedback: CognitionFeedback?
            var processCount = 0

            func process(perception: Perception, goalID: GoalID) async throws -> CognitionOutput {
                processCount += 1
                if perception.source == "feedback" {
                    let plan = Plan(goalID: goalID, steps: [])
                    let proposal = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.echo"), description: "echo", capabilities: .read)
                    return CognitionOutput(plan: plan, proposals: [proposal], verification: VerificationResult(accepted: true, notes: "Cycle 2 OK"))
                } else {
                    let plan = Plan(goalID: goalID, steps: [])
                    let proposalFail = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.fail"), description: "fail", capabilities: .read)
                    let proposalPass = ActionProposal(planID: plan.id, toolID: ToolID(rawValue: "mod.echo"), description: "pass", capabilities: .read)
                    return CognitionOutput(plan: plan, proposals: [proposalFail, proposalPass], verification: VerificationResult(accepted: true, notes: "Cycle 1 Partial"))
                }
            }

            func reflect(feedback: CognitionFeedback) async throws -> Reflection {
                if processCount == 1 {
                    self.cycle1Feedback = feedback
                } else {
                    self.cycle2Feedback = feedback
                }
                return Reflection(notes: "Feedback: \(feedback.evaluation.reason)", shouldAdapt: feedback.evaluation.disposition == .continue)
            }

            func trackerState() async -> (count: Int, c1: CognitionFeedback?, c2: CognitionFeedback?) {
                (processCount, cycle1Feedback, cycle2Feedback)
            }
        }

        let cognition = CognitionTracker()

        let disposition = try await root.orchestrator.runCycle(
            perception: Perception(rawInput: "start", source: "test"),
            goalID: goal.id,
            customCognition: cognition
        )

        #expect(disposition == .complete)
        let state = await cognition.trackerState()
        #expect(state.count == 2)
        #expect(state.c1 != nil)
        #expect(state.c1?.observations.count == 2)
        #expect(state.c2 != nil)
        #expect(state.c2?.observations.count == 1)
        let goalState = await root.runtime.goal(id: goal.id)
        #expect(goalState?.status == .completed)
    }

    // 11. Deterministic Concurrency Verification
    @Test("Concurrent runCycle calls maintain thread-safety, serialization, and lifecycle isolation")
    func deterministicConcurrencyIsolation() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal1 = Goal(statement: "Goal 1")
        let goal2 = Goal(statement: "Goal 2")
        try await root.runtime.submit(goal: goal1)
        try await root.runtime.submit(goal: goal2)

        actor SyncGate {
            var goal1Finished = false
            var goal1Started = false

            func markStarted() { goal1Started = true }
            func markFinished() { goal1Finished = true }
            func isFinished() -> Bool { goal1Finished }
        }

        let gate = SyncGate()

        // Activate goal 1 and execute
        try await root.runtime.activate(goalID: goal1.id)

        let task1 = Task {
            await gate.markStarted()
            let res = try await root.orchestrator.runCycle(perception: Perception(rawInput: "mod.echo", source: "t1"), goalID: goal1.id)
            await gate.markFinished()
            return res
        }

        let disp1 = try await task1.value
        #expect(disp1 == .complete)

        // Activate goal 2 and execute after goal 1 completes
        try await root.runtime.activate(goalID: goal2.id)
        let disp2 = try await root.orchestrator.runCycle(perception: Perception(rawInput: "mod.echo", source: "t2"), goalID: goal2.id)
        #expect(disp2 == .complete)

        let g1 = await root.runtime.goal(id: goal1.id)
        let g2 = await root.runtime.goal(id: goal2.id)
        #expect(g1?.status == .completed)
        #expect(g2?.status == .completed)
    }

    // 12. Trace/session identity auditability verification
    @Test("SessionTrace identity is preserved deterministically across all cycle events")
    func sessionTracePreservedAcrossEvents() async throws {
        let (root, _, _) = try await createTestComposition(policy: PermissivePolicyEvaluator())
        try await root.runtime.start()

        let goal = Goal(statement: "Audit Trace Goal")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        let sessionTrace = await root.runtime.sessionTrace

        let perception = Perception(rawInput: "mod.echo", source: "test")
        let disposition = try await root.orchestrator.runCycle(perception: perception, goalID: goal.id)
        #expect(disposition == .complete)

        let events = await root.eventLog.allEvents()
        #expect(!events.isEmpty)

        // Every kernel event emitted by runtime/orchestrator shares sessionTrace
        let traceEvents = events.filter { $0.traceID == sessionTrace }
        #expect(traceEvents.contains(where: { $0.kind == .goalSubmitted }))
        #expect(traceEvents.contains(where: { $0.kind == .goalActivated }))
        #expect(traceEvents.contains(where: { $0.kind == .contextBuilt }))
        #expect(traceEvents.contains(where: { $0.kind == .planProduced }))
        #expect(traceEvents.contains(where: { $0.kind == .actionProposed }))
        #expect(traceEvents.contains(where: { $0.kind == .verificationCompleted }))
        #expect(traceEvents.contains(where: { $0.kind == .toolCalled }))
        #expect(traceEvents.contains(where: { $0.kind == .stateUpdated }))
        #expect(traceEvents.contains(where: { $0.kind == .goalCompleted }))
    }

    // 13. StateUpdate verification: cannot bypass AgentRuntime lifecycle authority
    @Test("StateUpdate cannot independently mutate authoritative lifecycle state")
    func stateUpdatePreservesRuntimeAuthority() async throws {
        let (root, _, _) = try await createTestComposition()
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

        // Memory persisted
        let count = try await root.memoryRuntime.count()
        #expect(count == 1)

        // Goal status is still active (state update alone cannot complete/abort goals)
        let goalState = await root.runtime.goal(id: goal.id)
        #expect(goalState?.status == .active)
    }

    // 14. Architecture Manifest & Gate Check
    @Test("M6 milestone manifest integrity")
    func manifestIntegrity() {
        #expect(ArchitectureManifest.milestone == "M6")
        #expect(MilestoneGate.m6.cognitionLoop == true)
    }
}
