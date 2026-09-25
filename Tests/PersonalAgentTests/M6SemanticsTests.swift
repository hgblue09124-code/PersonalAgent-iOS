import PARuntime
import Foundation
import Testing
import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PASkills
import PATools
import PAComposition

@Suite("M6 Semantics and Issue #19 Blocker Tests")
struct M6SemanticsTests {

    // 1. Explicit toolID end-to-end without inference
    @Test func test1_ExplicitToolIDEndToEndWithoutInference() async throws {
        let root = try await M6CompositionRoot(modules: [EchoModule()])
        let goal = Goal(statement: "Perform custom action")
        try await root.runtime.submit(goal: goal)

        let explicitToolID = ToolID(rawValue: "mod.echo")
        let customProposer = DirectProposer(toolID: explicitToolID, description: "Completely unrelated description text 12345")
        let policySpy = PolicyCaptureSpy()

        let orchestrator = M6Orchestrator(
            runtime: root.runtime,
            eventLog: root.eventLog,
            proposer: customProposer,
            policy: policySpy,
            moduleRuntime: root.moduleRuntime
        )

        let eval = try await orchestrator.run(goalID: goal.id)
        #expect(eval.disposition == .complete)

        let capturedIntents = await policySpy.getCapturedIntents()
        #expect(capturedIntents.count == 1)
        #expect(capturedIntents.first?.toolID == explicitToolID)
        #expect(capturedIntents.first?.summary == "Completely unrelated description text 12345")

        let events = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let proposed = events.first { $0.kind == .actionProposed }
        let authorized = events.first { $0.kind == .actionAuthorized }
        let executed = events.first { $0.kind == .actionExecuted }

        #expect(proposed?.payload["toolID"] == "mod.echo")
        #expect(authorized?.payload["toolID"] == "mod.echo")
        #expect(executed?.payload["toolID"] == "mod.echo")
    }

    // 2. REAL Concurrent Goal Execution
    @Test func test2_RealConcurrentGoalExecution() async throws {
        let root1 = try await M6CompositionRoot(identity: AgentIdentity(displayName: "Agent 1"), modules: [EchoModule()])
        let root2 = try await M6CompositionRoot(identity: AgentIdentity(displayName: "Agent 2"), modules: [EchoModule()])

        let goal1 = Goal(statement: "Goal 1 concurrent")
        let goal2 = Goal(statement: "Goal 2 concurrent")
        try await root1.runtime.submit(goal: goal1)
        try await root2.runtime.submit(goal: goal2)

        let barrier = ExecutionBarrier(requiredCount: 2)
        let barrierProposer = BarrierProposer(barrier: barrier)

        let orchestrator1 = M6Orchestrator(
            runtime: root1.runtime,
            eventLog: root1.eventLog,
            proposer: barrierProposer,
            moduleRuntime: root1.moduleRuntime
        )
        let orchestrator2 = M6Orchestrator(
            runtime: root2.runtime,
            eventLog: root2.eventLog,
            proposer: barrierProposer,
            moduleRuntime: root2.moduleRuntime
        )

        // Run both goals concurrently in parallel Tasks
        async let run1 = orchestrator1.run(goalID: goal1.id)
        async let run2 = orchestrator2.run(goalID: goal2.id)

        let (eval1, eval2) = try await (run1, run2)

        #expect(eval1.disposition == .complete)
        #expect(eval2.disposition == .complete)

        let maxOverlap = await barrier.getMaxConcurrentExecutions()
        #expect(maxOverlap == 2, "Proves genuine simultaneous concurrent execution of both goals")

        let state1 = await root1.runtime.goal(id: goal1.id)?.status
        let state2 = await root2.runtime.goal(id: goal2.id)?.status
        #expect(state1 == .completed)
        #expect(state2 == .completed)
    }

    // 3. Prove Causal Audit Chain with Identity Linkage
    @Test func test3_CausalAuditChainWithIdentityLinkage() async throws {
        let root = try await M6CompositionRoot(modules: [EchoModule()])
        let goal = Goal(statement: "Audit chain test goal")
        try await root.runtime.submit(goal: goal)

        let eval = try await root.orchestrator.run(goalID: goal.id)
        #expect(eval.disposition == .complete)

        let allEvents = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let m6Events = allEvents.filter { event in
            [
                ExecutionEventKind.perceptionReceived,
                .contextBuilt,
                .planProduced,
                .actionProposed,
                .actionAuthorized,
                .actionExecuted,
                .observationProduced,
                .evaluationCompleted,
                .reflectionCompleted,
                .stateUpdated,
            ].contains(event.kind)
        }

        #expect(!m6Events.isEmpty)

        guard let proposed = m6Events.first(where: { $0.kind == .actionProposed }),
              let authorized = m6Events.first(where: { $0.kind == .actionAuthorized }),
              let executed = m6Events.first(where: { $0.kind == .actionExecuted }),
              let observation = m6Events.first(where: { $0.kind == .observationProduced }),
              let evaluation = m6Events.first(where: { $0.kind == .evaluationCompleted }),
              let reflection = m6Events.first(where: { $0.kind == .reflectionCompleted }),
              let stateUpdated = m6Events.first(where: { $0.kind == .stateUpdated }) else {
            Issue.record("Missing required causal event chain")
            return
        }

        let actionID = proposed.payload["actionID"]
        let planID = proposed.payload["planID"]
        let goalID = proposed.payload["goalID"]

        #expect(actionID != nil)
        #expect(planID != nil)
        #expect(goalID == goal.id.rawValue)

        #expect(authorized.payload["actionID"] == actionID)
        #expect(authorized.payload["goalID"] == goalID)

        #expect(executed.payload["actionID"] == actionID)
        #expect(executed.payload["goalID"] == goalID)

        #expect(observation.payload["actionID"] == actionID)
        #expect(observation.payload["goalID"] == goalID)

        #expect(evaluation.payload["goalID"] == goalID)
        #expect(reflection.payload["goalID"] == goalID)
        #expect(stateUpdated.payload["goalID"] == goalID)
    }

    // 4. Fail-closed Audit Persistence
    @Test func test4_FailClosedAuditPersistence() async throws {
        let failingLog = FailingEventLog(failAfter: 2)
        let agentRuntime = try await AgentRuntime(
            identity: AgentIdentity(displayName: "Failing Log Agent"),
            eventLog: failingLog
        )

        let goal = Goal(statement: "Goal for failing log")
        try await agentRuntime.submit(goal: goal)

        let orchestrator = M6Orchestrator(
            runtime: agentRuntime,
            eventLog: failingLog
        )

        await #expect(throws: FailingEventLogError.self) {
            try await orchestrator.run(goalID: goal.id)
        }

        let finalStatus = await agentRuntime.goal(id: goal.id)?.status
        #expect(finalStatus != .completed, "Goal must not reach .completed status when audit event fails to persist")
    }

    // 5. Authoritative StateUpdate
    @Test func test5_AuthoritativeStateUpdate() async throws {
        let root = try await M6CompositionRoot()
        let goal = Goal(statement: "State update test")
        try await root.runtime.submit(goal: goal)
        try await root.runtime.activate(goalID: goal.id)

        // Empty evidence must be rejected
        let invalidUpdate = StateUpdate(goalID: goal.id, targetStatus: .completed, evidence: [:])
        await #expect(throws: KernelError.self) {
            try await root.runtime.applyStateUpdate(invalidUpdate)
        }

        #expect(await root.runtime.goal(id: goal.id)?.status == .active)

        // Valid update with required evidence must succeed
        let validUpdate = StateUpdate(
            goalID: goal.id,
            targetStatus: .completed,
            evidence: [
                "disposition": "complete",
                "reason": "Successfully verified evidence",
                "reflection": "Reflection verified",
            ]
        )
        try await root.runtime.applyStateUpdate(validUpdate)

        #expect(await root.runtime.goal(id: goal.id)?.status == .completed)

        let events = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let stateEvent = events.first { $0.kind == .stateUpdated }
        #expect(stateEvent?.payload["goalID"] == goal.id.rawValue)
        #expect(stateEvent?.payload["targetStatus"] == GoalStatus.completed.rawValue)
        #expect(stateEvent?.payload["disposition"] == "complete")
    }

    // 6. Verification Rejection & Policy Denial Fail Closed
    @Test func test6_VerificationRejectionAndPolicyDenial() async throws {
        let root = try await M6CompositionRoot()
        let goal = Goal(statement: "Verification rejection goal")
        try await root.runtime.submit(goal: goal)

        let rejectingVerifier = CustomVerifier(accept: false, notes: "Unsafe operational parameters")
        let orchestrator = M6Orchestrator(
            runtime: root.runtime,
            eventLog: root.eventLog,
            verifier: rejectingVerifier
        )

        let eval = try await orchestrator.run(goalID: goal.id)
        #expect(eval.disposition == .abort)
        #expect(eval.reason == "Verification rejected")

        let status = await root.runtime.goal(id: goal.id)?.status
        #expect(status == .aborted)

        let events = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        #expect(events.contains { $0.kind == .verificationCompleted && $0.payload["accepted"] == "false" })
        #expect(!events.contains { $0.kind == .actionExecuted })
    }

    // 7. Multi-cycle Continuation Loop with Feedback
    @Test func test7_MultiCycleContinuationLoop() async throws {
        let root = try await M6CompositionRoot()
        let goal = Goal(statement: "Multi cycle goal")
        try await root.runtime.submit(goal: goal)

        let multiEvaluator = MultiCycleEvaluator(continueForCycles: 1)
        let feedbackAssembler = FeedbackContextAssemblerSpy()

        let orchestrator = M6Orchestrator(
            runtime: root.runtime,
            eventLog: root.eventLog,
            contextAssembler: feedbackAssembler,
            evaluator: multiEvaluator,
            maxCycles: 3
        )

        let eval = try await orchestrator.run(goalID: goal.id)
        #expect(eval.disposition == .complete)

        let events = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let perceptionCount = events.filter { $0.kind == .perceptionReceived }.count
        #expect(perceptionCount == 2, "Proves multi-cycle continuation loop executed exactly 2 cognitive cycles")

        let receivedFeedbackCount = await feedbackAssembler.getFeedbackCount()
        #expect(receivedFeedbackCount == 2)
    }

    // B1 Regression Test: Prove custom EventLog receives events via M6CompositionRoot
    @Test func testB1_CustomEventLogInjectionProof() async throws {
        let customLog = CustomInjectableEventLog()
        let root = try await M6CompositionRoot(
            eventLog: customLog,
            modules: [EchoModule()]
        )

        let goal = Goal(statement: "B1 custom log test")
        try await root.runtime.submit(goal: goal)
        let eval = try await root.orchestrator.run(goalID: goal.id)

        #expect(eval.disposition == .complete)

        let recordedEvents = await customLog.allEvents()
        #expect(!recordedEvents.isEmpty, "Custom injected EventLog must record events")
        #expect(recordedEvents.contains { $0.kind == .runtimeInitialized })
        #expect(recordedEvents.contains { $0.kind == .goalSubmitted })
        #expect(recordedEvents.contains { $0.kind == .actionExecuted })
    }

    // B2 Regression Test: Prove AgentRuntime.applyStateUpdate does not commit state if audit persistence fails
    @Test func testB2_FailClosedStateUpdateAuditPersistence() async throws {
        let failingLog = FailingEventLog(failAfter: 2)
        let agentRuntime = try await AgentRuntime(
            identity: AgentIdentity(displayName: "B2 Failing Log Agent"),
            eventLog: failingLog
        )
        try await agentRuntime.start()

        let goal = Goal(statement: "State update audit failure goal")
        await #expect(throws: FailingEventLogError.self) {
            try await agentRuntime.submit(goal: goal)
        }

        #expect(await agentRuntime.goal(id: goal.id) == nil, "Goal must not be committed to goalStore when submit audit logging fails")

        let logForUpdate = FailingEventLog(failAfter: 4)
        let runtime2 = try await AgentRuntime(
            identity: AgentIdentity(displayName: "B2 Agent 2"),
            eventLog: logForUpdate
        )
        try await runtime2.start()
        let goal2 = Goal(statement: "Goal 2 for applyStateUpdate test")
        try await runtime2.submit(goal: goal2)
        try await runtime2.activate(goalID: goal2.id)

        #expect(await runtime2.goal(id: goal2.id)?.status == .active)

        let update = StateUpdate(
            goalID: goal2.id,
            targetStatus: .completed,
            evidence: ["reason": "Attempting completion"]
        )

        await #expect(throws: FailingEventLogError.self) {
            try await runtime2.applyStateUpdate(update)
        }

        #expect(await runtime2.goal(id: goal2.id)?.status == .active, "Authoritative state must remain .active and not be committed to .completed when audit persistence fails")
    }

    // 8. Missing Execution Target Fails Closed
    @Test func test8_MissingExecutionTargetFailsClosed() async throws {
        let root = try await M6CompositionRoot() // No modules registered
        let goal = Goal(statement: "Unregistered tool goal")
        try await root.runtime.submit(goal: goal)

        let missingToolID = ToolID(rawValue: "unregistered.tool")
        let proposer = DirectProposer(toolID: missingToolID, description: "Invoke unregistered tool")

        let orchestrator = M6Orchestrator(
            runtime: root.runtime,
            eventLog: root.eventLog,
            proposer: proposer,
            moduleRuntime: root.moduleRuntime
        )

        let eval = try await orchestrator.run(goalID: goal.id)
        #expect(eval.disposition == .abort, "Missing execution target must cause evaluation to abort")

        let events = await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let obsEvent = events.first { $0.kind == .observationProduced }
        #expect(obsEvent?.payload["succeeded"] == "false")
        #expect(obsEvent?.payload["summary"]?.contains("Execution target unavailable") == true)
    }
}

// MARK: - Test Helpers & Doubles

private struct DirectProposer: Executing {
    let toolID: ToolID
    let description: String

    func propose(plan: Plan) async throws -> [ActionProposal] {
        [
            ActionProposal(
                planID: plan.id,
                toolID: toolID,
                description: description,
                capabilities: .execute
            )
        ]
    }
}

private actor PolicyCaptureSpy: PolicyEvaluating {
    private var capturedIntents: [ActionIntent] = []

    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        capturedIntents.append(intent)
        return .allow("Permitted")
    }

    func getCapturedIntents() -> [ActionIntent] {
        capturedIntents
    }
}

private actor ExecutionBarrier {
    private let requiredCount: Int
    private var arrivedCount: Int = 0
    private var activeCount: Int = 0
    private var maxConcurrent: Int = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(requiredCount: Int) {
        self.requiredCount = requiredCount
    }

    func enter() async {
        arrivedCount += 1
        activeCount += 1
        if activeCount > maxConcurrent {
            maxConcurrent = activeCount
        }

        if arrivedCount >= requiredCount {
            for cont in continuations {
                cont.resume()
            }
            continuations.removeAll()
        } else {
            await withCheckedContinuation { cont in
                continuations.append(cont)
            }
        }
    }

    func leave() {
        activeCount -= 1
    }

    func getMaxConcurrentExecutions() -> Int {
        maxConcurrent
    }
}

private struct BarrierProposer: Executing {
    let barrier: ExecutionBarrier

    func propose(plan: Plan) async throws -> [ActionProposal] {
        await barrier.enter()
        defer { Task { await barrier.leave() } }
        return [
            ActionProposal(
                planID: plan.id,
                toolID: ToolID(rawValue: "mod.echo"),
                description: "Barrier step",
                capabilities: .read
            )
        ]
    }
}

private struct CustomVerifier: Verifying {
    let accept: Bool
    let notes: String

    func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult {
        VerificationResult(accepted: accept, notes: notes)
    }
}

private actor MultiCycleEvaluator: Evaluating {
    private let continueForCycles: Int
    private var currentCycle: Int = 0

    init(continueForCycles: Int) {
        self.continueForCycles = continueForCycles
    }

    func evaluate(goalID: GoalID, observations: [Observation]) async throws -> Evaluation {
        currentCycle += 1
        if currentCycle <= continueForCycles {
            return Evaluation(goalID: goalID, disposition: .continue, reason: "Continuing cycle \(currentCycle)")
        } else {
            return Evaluation(goalID: goalID, disposition: .complete, reason: "Finished after \(currentCycle) cycles")
        }
    }
}

private actor FeedbackContextAssemblerSpy: ContextAssembling {
    private var feedbackCalls: [(observations: [Observation], evaluation: Evaluation?)] = []

    func assembleContext(
        perception: Perception,
        observations: [Observation],
        evaluation: Evaluation?
    ) async throws -> ContextBundle {
        feedbackCalls.append((observations, evaluation))
        return ContextBundle(perception: perception, memoryIDs: [], skillIDs: [])
    }

    func getFeedbackCount() -> Int {
        feedbackCalls.count
    }
}

private struct FailingEventLogError: Error, Equatable {}

private actor FailingEventLog: EventLog {
    private var eventsList: [ExecutionEvent] = []
    private var appendCount = 0
    private let failAfter: Int

    init(failAfter: Int) {
        self.failAfter = failAfter
    }

    func append(_ event: ExecutionEvent) async throws {
        appendCount += 1
        if appendCount > failAfter {
            throw FailingEventLogError()
        }
        eventsList.append(event)
    }

    func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        eventsList
    }

    func allEvents() async -> [ExecutionEvent] {
        eventsList
    }
}


// MARK: - B1 Custom EventLog Test Double

private actor CustomInjectableEventLog: EventLog {
    private var eventsRecorded: [ExecutionEvent] = []

    init() {}

    func append(_ event: ExecutionEvent) async throws {
        eventsRecorded.append(event)
    }

    func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        eventsRecorded.filter { $0.traceID == traceID }
    }

    func allEvents() async -> [ExecutionEvent] {
        eventsRecorded
    }
}
