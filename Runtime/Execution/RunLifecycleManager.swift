import Foundation
import PAKernel
import PAObservability
import PAEvents
import PAModules

public actor RunLifecycleManager {
    private let runtime: AgentRuntime
    private let runStore: any RunStore
    private let checkpointStore: any RunCheckpointStore
    private let journalStore: any StateJournalStore
    private let executionBoundary: ExecutionBoundary
    private let eventLog: any EventLog
    private let logger: any AgentLogger
    private let contextAssembler: any ContextAssembling
    private let reasoner: any Reasoning
    private let planner: any Planning
    private let proposer: any Executing
    private let verifier: any Verifying
    private let evaluator: any Evaluating
    private let reflector: any Reflecting
    private let maxCycles: Int

    public init(
        runtime: AgentRuntime,
        runStore: any RunStore,
        checkpointStore: any RunCheckpointStore,
        journalStore: any StateJournalStore,
        executionBoundary: ExecutionBoundary,
        eventLog: any EventLog = InMemoryEventLog(),
        logger: any AgentLogger = NullLoggerBridge(),
        contextAssembler: (any ContextAssembling)? = nil,
        reasoner: (any Reasoning)? = nil,
        planner: (any Planning)? = nil,
        proposer: (any Executing)? = nil,
        verifier: (any Verifying)? = nil,
        evaluator: (any Evaluating)? = nil,
        reflector: (any Reflecting)? = nil,
        maxCycles: Int = 3
    ) {
        self.runtime = runtime
        self.runStore = runStore
        self.checkpointStore = checkpointStore
        self.journalStore = journalStore
        self.executionBoundary = executionBoundary
        self.eventLog = eventLog
        self.logger = logger
        self.contextAssembler = contextAssembler ?? DefaultContextAssembler()
        self.reasoner = reasoner ?? DefaultReasoner()
        self.planner = planner ?? DefaultPlanner()
        self.proposer = proposer ?? DefaultProposer()
        self.verifier = verifier ?? DefaultVerifier()
        self.evaluator = evaluator ?? DefaultEvaluator()
        self.reflector = reflector ?? DefaultReflector()
        self.maxCycles = maxCycles
    }

    public func createRun(goalID: GoalID, sessionID: SessionID = SessionID()) async throws -> RunRecord {
        guard let goal = await runtime.goal(id: goalID) else {
            throw KernelError.goalNotFound(goalID)
        }

        let runID = RunID()
        let traceID = TraceID()
        var record = RunRecord(
            runID: runID,
            sessionID: sessionID,
            goalID: goalID,
            traceID: traceID,
            status: .initialized,
            currentCycle: 0
        )

        try await runStore.save(record)

        let initEvent = ExecutionEvent(
            traceID: traceID,
            kind: .runtimeInitialized,
            payload: [
                "runID": runID.rawValue,
                "goalID": goalID.rawValue,
                "sessionID": sessionID.rawValue,
                "status": record.status.rawValue,
            ]
        )
        try await eventLog.append(initEvent)

        if goal.status == .proposed {
            try await runtime.activate(goalID: goalID)
        }

        record.status = .running
        record.updatedAt = Date()
        try await runStore.save(record)

        return record
    }

    /// Canonical production entry point. Every app execution must acquire a
    /// durable run identity and capability lease before entering the execution cycle.
    public func run(
        goalID: GoalID,
        sessionID: SessionID = SessionID(),
        rawInput: String? = nil
    ) async throws -> Evaluation {
        let record = try await createRun(goalID: goalID, sessionID: sessionID)
        let lease = CapabilityLease(runID: record.runID)
        return try await runCycle(runID: record.runID, lease: lease, rawInput: rawInput)
    }

    public func runCycle(
        runID: RunID,
        lease: CapabilityLease,
        rawInput: String? = nil
    ) async throws -> Evaluation {
        guard var record = try await runStore.record(for: runID) else {
            throw KernelError.goalNotFound(GoalID(rawValue: "unknown"))
        }

        let goalID = record.goalID
        let traceID = record.traceID

        try Task.checkCancellation()
        try await waitUntilRunnable()

        guard let goal = await runtime.goal(id: goalID) else {
            throw KernelError.goalNotFound(goalID)
        }

        // Reconcile status with AgentRuntime
        if goal.status == .completed {
            record.status = .completed
            try await runStore.save(record)
            return Evaluation(goalID: goalID, disposition: .complete, reason: "Goal already completed in AgentRuntime")
        }
        if goal.status == .aborted {
            record.status = .failed
            try await runStore.save(record)
            return Evaluation(goalID: goalID, disposition: .abort, reason: "Goal already aborted in AgentRuntime")
        }

        let cycleIndex = record.currentCycle + 1
        guard cycleIndex <= maxCycles else {
            let reason = "Maximum run cycles (\(maxCycles)) exceeded"
            let evaluation = Evaluation(goalID: goalID, disposition: .abort, reason: reason)
            try await commitStateUpdate(
                runID: runID,
                goalID: goalID,
                traceID: traceID,
                targetStatus: .aborted,
                disposition: .abort,
                reason: reason,
                evidence: [
                    "maxCycles": String(maxCycles),
                    "currentCycle": String(record.currentCycle)
                ]
            )
            record.status = .failed
            record.updatedAt = Date()
            try await runStore.save(record)
            return evaluation
        }
        record.currentCycle = cycleIndex
        record.status = .running
        try await runStore.save(record)

        let input = rawInput ?? goal.statement
        let perception = Perception(rawInput: input, source: "user")

        try Task.checkCancellation()

        // 1. Perception & Context
        let context = try await contextAssembler.assembleContext(perception: perception, observations: [], evaluation: nil)

        try Task.checkCancellation()

        // 2. Reasoning & Planning
        let reasoningResult = try await reasoner.reason(context: context)
        let plan = try await planner.plan(goalID: goalID, context: context, reasoning: reasoningResult)

        try Task.checkCancellation()
        try await waitUntilRunnable()

        // 3. ActionProposals
        let proposals = try await proposer.propose(plan: plan)

        try Task.checkCancellation()

        // 4. Verification
        let verification = try await verifier.verify(plan: plan, proposals: proposals)
        if !verification.accepted {
            let eval = Evaluation(goalID: goalID, disposition: .abort, reason: "Verification rejected")
            try await commitStateUpdate(
                runID: runID,
                goalID: goalID,
                traceID: traceID,
                targetStatus: .aborted,
                disposition: .abort,
                reason: eval.reason,
                evidence: ["verificationNotes": verification.notes]
            )
            record.status = .failed
            try await runStore.save(record)
            return eval
        }

        // 5. Pre-Execution Checkpoint
        let preCheckpoint = RunCheckpoint(
            runID: runID,
            goalID: goalID,
            traceID: traceID,
            cycleIndex: cycleIndex,
            pendingProposals: proposals,
            completedObservations: []
        )
        try await checkpointStore.saveCheckpoint(preCheckpoint)
        record.status = .checkpointed
        try await runStore.save(record)

        // 6. Execution Loop via ExecutionBoundary
        try Task.checkCancellation()
        try await waitUntilRunnable()
        var observations: [Observation] = []
        for proposal in proposals {
            try Task.checkCancellation()
            try await waitUntilRunnable()
            let (obs, _) = try await executionBoundary.executeProposal(
                proposal: proposal,
                runID: runID,
                goalID: goalID,
                traceID: traceID,
                cycleIndex: cycleIndex,
                lease: lease
            )
            observations.append(obs)
        }

        try Task.checkCancellation()

        // 7. Post-Execution Checkpoint
        let postCheckpoint = RunCheckpoint(
            runID: runID,
            goalID: goalID,
            traceID: traceID,
            cycleIndex: cycleIndex,
            pendingProposals: [],
            completedObservations: observations
        )
        try await checkpointStore.saveCheckpoint(postCheckpoint)

        try Task.checkCancellation()
        try await waitUntilRunnable()

        // 8. Evaluation & Reflection
        let evaluated = try await evaluator.evaluate(goalID: goalID, observations: observations)
        let evaluation = try RunResultPresentation.makeUserVisible(
            evaluation: evaluated,
            reasoningSummary: reasoningResult.summary,
            proposals: proposals,
            observations: observations
        )
        let reflection = try await reflector.reflect(goalID: goalID, observations: observations, evaluation: evaluation)

        try Task.checkCancellation()
        try await waitUntilRunnable()

        // 9. WAL StateUpdate Transaction
        let targetGoalStatus: GoalStatus
        switch evaluation.disposition {
        case .complete:
            targetGoalStatus = .completed
        case .abort:
            targetGoalStatus = .aborted
        case .continue:
            targetGoalStatus = .active
        }

        try await commitStateUpdate(
            runID: runID,
            goalID: goalID,
            traceID: traceID,
            targetStatus: targetGoalStatus,
            disposition: evaluation.disposition,
            reason: evaluation.reason,
            evidence: [
                "reflectionNotes": reflection.notes,
                "observationIDs": observations.map(\.actionID.rawValue).joined(separator: ","),
            ]
        )

        // Update run state
        switch evaluation.disposition {
        case .complete:
            record.status = .completed
        case .abort:
            record.status = .failed
        case .continue:
            record.status = .running
        }

        record.updatedAt = Date()
        try await runStore.save(record)

        return evaluation
    }

    private func waitUntilRunnable() async throws {
        while true {
            try Task.checkCancellation()
            switch await runtime.currentState().lifecycle {
            case .running:
                return
            case .paused:
                try await Task.sleep(for: .milliseconds(100))
            case .stopped, .failed:
                throw KernelError.runtimeNotExecutable(await runtime.currentState().lifecycle)
            case .created, .starting, .pausing, .stopping:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func commitStateUpdate(
        runID: RunID,
        goalID: GoalID,
        traceID: TraceID,
        targetStatus: GoalStatus,
        disposition: AgencyDisposition,
        reason: String,
        evidence: [String: String]
    ) async throws {
        let eventID = EventID()
        let auditPayload: [String: String] = [
            "disposition": disposition.rawValue,
            "goalID": goalID.rawValue,
            "reason": reason,
            "targetStatus": targetStatus.rawValue,
        ]
        let canonicalPayload = IdempotentEventLog.canonicalString(for: auditPayload)

        var journalEntry = StateJournalEntry(
            runID: runID,
            goalID: goalID,
            targetStatus: targetStatus,
            eventID: eventID,
            canonicalEventPayload: canonicalPayload,
            evidence: evidence,
            status: .prepared
        )
        try await journalStore.saveEntry(journalEntry)

        var fullEvidence = evidence
        fullEvidence["disposition"] = disposition.rawValue
        fullEvidence["reason"] = reason

        let update = StateUpdate(
            goalID: goalID,
            targetStatus: targetStatus,
            evidence: fullEvidence,
            mutationToken: journalEntry.journalID
        )

        // Apply state update to AgentRuntime - AgentRuntime remains sole authority!
        try await runtime.applyStateUpdate(update)

        journalEntry.status = .stateCommitted
        journalEntry.updatedAt = Date()
        try await journalStore.saveEntry(journalEntry)

        // Audit Event Log with STABLE EventID and canonical payload
        let auditEvent = ExecutionEvent(
            id: eventID,
            traceID: traceID,
            kind: .stateUpdated,
            timestamp: Date(),
            payload: auditPayload
        )
        try await eventLog.append(auditEvent)

        journalEntry.status = .auditCommitted
        journalEntry.updatedAt = Date()
        try await journalStore.saveEntry(journalEntry)

        journalEntry.status = .finalized
        journalEntry.updatedAt = Date()
        try await journalStore.saveEntry(journalEntry)
    }
}


/// Chooses a user-facing result only from the artifact appropriate to the run.
/// Failed/aborted runs must never surface a model answer or tool output as success.
enum RunResultPresentation {
    static func makeUserVisible(
        evaluation: Evaluation,
        reasoningSummary: String,
        proposals: [ActionProposal],
        observations: [Observation]
    ) throws -> Evaluation {
        if proposals.allSatisfy({ $0.toolID == nil }) {
            guard evaluation.disposition == .complete else {
                return evaluation
            }
            let answer = reasoningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                throw KernelError.invalidStateUpdate("Answer-only reasoning returned empty output")
            }
            return Evaluation(
                goalID: evaluation.goalID,
                disposition: evaluation.disposition,
                reason: answer
            )
        }

        guard evaluation.disposition == .complete else {
            let failures = observations
                .filter { !$0.succeeded }
                .map { $0.summary.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !failures.isEmpty else { return evaluation }
            return Evaluation(
                goalID: evaluation.goalID,
                disposition: evaluation.disposition,
                reason: failures.joined(separator: "\n")
            )
        }

        let toolActionIDs = Set(proposals.filter { $0.toolID != nil }.map(\.actionID))
        let toolObservations = observations.filter { toolActionIDs.contains($0.actionID) }
        guard !toolActionIDs.isEmpty,
              toolObservations.count == toolActionIDs.count,
              toolObservations.allSatisfy(\.succeeded) else {
            throw KernelError.invalidStateUpdate("Agent marked tool execution complete without verified results")
        }
        let results = toolObservations
            .map { $0.summary.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard results.allSatisfy({ !$0.isEmpty }) else {
            throw KernelError.invalidStateUpdate("Verified tool execution returned an empty result")
        }
        return Evaluation(
            goalID: evaluation.goalID,
            disposition: evaluation.disposition,
            reason: results.joined(separator: "\n")
        )
    }
}
