import Foundation
import PAFoundation
import PAObservability
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules

public actor ExecutionBoundary {
    private let attemptStore: any ExecutionAttemptStore
    private let policy: any PolicyEvaluating
    private let approvalGate: (any ApprovalGate)?
    private let moduleRuntime: ModuleRuntime?
    private let evidenceResolver: (any ExecutionEvidenceResolver)?
    private let eventLog: any EventLog
    private let targetCapabilities: [ToolID: ExecutionTargetCapability]

    public init(
        attemptStore: any ExecutionAttemptStore,
        policy: any PolicyEvaluating = DefaultPolicyEvaluator(),
        approvalGate: (any ApprovalGate)? = nil,
        moduleRuntime: ModuleRuntime? = nil,
        evidenceResolver: (any ExecutionEvidenceResolver)? = nil,
        eventLog: any EventLog = InMemoryEventLog(),
        targetCapabilities: [ExecutionTargetCapability] = []
    ) {
        self.attemptStore = attemptStore
        self.policy = policy
        self.approvalGate = approvalGate
        self.moduleRuntime = moduleRuntime
        self.evidenceResolver = evidenceResolver
        self.eventLog = eventLog

        var capMap: [ToolID: ExecutionTargetCapability] = [:]
        for cap in targetCapabilities {
            capMap[cap.toolID] = cap
        }
        self.targetCapabilities = capMap
    }

    public func targetCapability(for toolID: ToolID) -> ExecutionTargetCapability? {
        if let cap = targetCapabilities[toolID] {
            return cap
        }
        if let cap = targetCapabilities[ToolID(rawValue: "tool." + toolID.rawValue)] {
            return cap
        }
        let stripped = toolID.rawValue.hasPrefix("tool.") ? String(toolID.rawValue.dropFirst(5)) : toolID.rawValue
        if let cap = targetCapabilities[ToolID(rawValue: stripped)] {
            return cap
        }
        return nil
    }

    public func computeIdempotencyKey(
        runID: RunID,
        goalID: GoalID,
        cycleIndex: Int,
        proposal: ActionProposal
    ) -> String {
        let raw = "\(runID.rawValue):\(goalID.rawValue):\(cycleIndex):\(proposal.actionID.rawValue):\(proposal.toolID?.rawValue ?? "none")"
        return raw
    }

    public func executeProposal(
        proposal: ActionProposal,
        runID: RunID,
        goalID: GoalID,
        traceID: TraceID,
        cycleIndex: Int,
        lease: CapabilityLease
    ) async throws -> (Observation, ExecutionAttempt) {
        let idempotencyKey = computeIdempotencyKey(
            runID: runID,
            goalID: goalID,
            cycleIndex: cycleIndex,
            proposal: proposal
        )

        // 0. Target Capability Check (Missing capability -> Fail Closed)
        var targetCap: ExecutionTargetCapability? = nil
        if let toolID = proposal.toolID {
            guard let cap = targetCapability(for: toolID) else {
                let obsSummary = "Missing target capability declaration for tool '\(toolID.rawValue)': fail closed"
                let attempt = ExecutionAttempt(
                    runID: runID,
                    actionID: proposal.actionID,
                    toolID: proposal.toolID,
                    idempotencyKey: idempotencyKey,
                    status: .failed,
                    startedAt: Date(),
                    completedAt: Date(),
                    eventID: EventID()
                )
                try await attemptStore.saveAttempt(attempt)
                let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                return (obs, attempt)
            }
            targetCap = cap
        }

        // 1. Policy & Approval check
        let intent = ActionIntent(
            actionID: proposal.actionID,
            toolID: proposal.toolID,
            capabilities: proposal.capabilities,
            summary: proposal.description
        )

        let decision = await policy.evaluate(intent)
        var allowed = decision.allowed

        if decision.requiresApproval {
            if let gate = approvalGate {
                allowed = try await gate.requestApproval(for: intent)
            } else {
                // FAIL CLOSED: Approval required but no approval gate provided
                allowed = false
            }
        }

        if !allowed {
            let attempt = ExecutionAttempt(
                runID: runID,
                actionID: proposal.actionID,
                toolID: proposal.toolID,
                idempotencyKey: idempotencyKey,
                status: .failed,
                startedAt: Date(),
                completedAt: Date(),
                eventID: EventID()
            )
            try await attemptStore.saveAttempt(attempt)
            let obs = Observation(
                actionID: proposal.actionID,
                summary: "Denied by policy: \(decision.reason)",
                succeeded: false
            )
            return (obs, attempt)
        }

        // Consume step atomically before dispatch (validates lease expiration, revocation, step count)
        try await lease.consume(step: 1, forRunID: runID)

        // Pre-dispatch target & infrastructure validation BEFORE transitioning to STARTED_UNKNOWN
        var targetContract: ModuleContract? = nil
        if let toolID = proposal.toolID {
            guard let modules = moduleRuntime else {
                let obsSummary = "Execution target unavailable: moduleRuntime is missing for tool '\(toolID.rawValue)'"
                let attempt = ExecutionAttempt(
                    runID: runID,
                    actionID: proposal.actionID,
                    toolID: proposal.toolID,
                    idempotencyKey: idempotencyKey,
                    status: .failed,
                    startedAt: Date(),
                    completedAt: Date(),
                    eventID: EventID()
                )
                try await attemptStore.saveAttempt(attempt)
                let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                return (obs, attempt)
            }

            let contracts = await modules.contracts()
            guard let contract = contracts.first(where: { $0.id.rawValue == toolID.rawValue || $0.id.rawValue == "tool." + toolID.rawValue }) else {
                let obsSummary = "Execution target unavailable: tool '\(toolID.rawValue)' not registered in ModuleCatalog"
                let attempt = ExecutionAttempt(
                    runID: runID,
                    actionID: proposal.actionID,
                    toolID: proposal.toolID,
                    idempotencyKey: idempotencyKey,
                    status: .failed,
                    startedAt: Date(),
                    completedAt: Date(),
                    eventID: EventID()
                )
                try await attemptStore.saveAttempt(attempt)
                let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                return (obs, attempt)
            }
            targetContract = contract
        }

        // Check if an attempt for this idempotency key already exists (retry of same attempt)
        let existingAttempt = try await attemptStore.attempt(forIdempotencyKey: idempotencyKey)
        let attemptID = existingAttempt?.attemptID ?? ExecutionAttemptID()
        let eventID = existingAttempt?.eventID ?? EventID()

        // 2. Initialize attempt as NOT_STARTED on disk
        var attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: runID,
            actionID: proposal.actionID,
            toolID: proposal.toolID,
            idempotencyKey: idempotencyKey,
            status: .notStarted,
            eventID: eventID
        )
        try await attemptStore.saveAttempt(attempt)

        // 3. Mark attempt as STARTED_UNKNOWN immediately prior to dispatch
        attempt.status = .startedUnknown
        attempt.startedAt = Date()
        try await attemptStore.saveAttempt(attempt)

        // 4. Dispatch side effect
        if let toolID = proposal.toolID, let targetContract = targetContract, let modules = moduleRuntime, let cap = targetCap {
            let schema = targetContract.inputSchema
            var fields = [
                "text": proposal.description,
                "input": proposal.description,
                "message": proposal.description,
            ]
            for req in targetContract.requiredFields {
                if fields[req] == nil {
                    fields[req] = proposal.description
                }
            }

            let invocation = ModuleInvocation(
                moduleID: targetContract.id,
                input: ModulePayload(schema: schema, fields: fields)
            )

            do {
                let res = try await modules.execute(invocation)
                let obsSummary = res.output.fields["output"] ?? res.output.fields["result"] ?? res.output.fields["message"] ?? res.output.fields["text"] ?? "Success"
                let executorSucceeded = (res.state == .completed)

                if executorSucceeded {
                    // Save receipt as execution evidence
                    let receipt = ExecutionReceipt(
                        attemptID: attempt.attemptID,
                        toolID: toolID,
                        idempotencyKey: idempotencyKey,
                        timestamp: Date(),
                        outputSummary: obsSummary,
                        rawOutputFields: res.output.fields
                    )
                    try await attemptStore.saveReceipt(receipt)
                    attempt.receiptRef = receipt.receiptID

                    // Independent Verification / Evidence Resolution
                    // Executor Success != Verified Success!
                    let verificationResolution = await resolveEvidence(attempt: attempt)

                    switch verificationResolution {
                    case .completed:
                        attempt.status = .completed
                        attempt.completedAt = Date()
                        try await attemptStore.saveAttempt(attempt)
                        let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: true)
                        return (obs, attempt)

                    case .notStarted:
                        // CONTRADICTION: Executor completed but evidence resolution returned notStarted!
                        attempt.status = .unresolved
                        try await attemptStore.saveAttempt(attempt)
                        let obs = Observation(
                            actionID: proposal.actionID,
                            summary: "Execution contradiction: executor completed but evidence resolution returned notStarted",
                            succeeded: false
                        )
                        return (obs, attempt)

                    case .unknown, .unavailable:
                        if cap.idempotencyClass == .idempotent {
                            attempt.status = .startedUnknown
                        } else {
                            attempt.status = .unresolved
                        }
                        try await attemptStore.saveAttempt(attempt)
                        let obs = Observation(
                            actionID: proposal.actionID,
                            summary: "Execution unverified (\(verificationResolution)): \(obsSummary)",
                            succeeded: false
                        )
                        return (obs, attempt)
                    }
                } else {
                    // Executor returned failed / non-completed state. Check independent evidence first!
                    let verificationResolution = await resolveEvidence(attempt: attempt)

                    if case .completed(let receipt) = verificationResolution {
                        attempt.status = .completed
                        attempt.completedAt = Date()
                        attempt.receiptRef = receipt.receiptID
                        try await attemptStore.saveAttempt(attempt)
                        let obs = Observation(actionID: proposal.actionID, summary: receipt.outputSummary, succeeded: true)
                        return (obs, attempt)
                    }

                    attempt.status = .failed
                    attempt.completedAt = Date()
                    try await attemptStore.saveAttempt(attempt)

                    let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                    return (obs, attempt)
                }
            } catch {
                // Dispatch threw exception or timed out. Check independent evidence!
                let verificationResolution = await resolveEvidence(attempt: attempt)

                if case .completed(let receipt) = verificationResolution {
                    attempt.status = .completed
                    attempt.completedAt = Date()
                    attempt.receiptRef = receipt.receiptID
                    try await attemptStore.saveAttempt(attempt)
                    let obs = Observation(actionID: proposal.actionID, summary: receipt.outputSummary, succeeded: true)
                    return (obs, attempt)
                }

                // Exception during execution: attempt status MUST REMAIN STARTED_UNKNOWN (if idempotent) or UNRESOLVED (if non-idempotent)!
                if cap.idempotencyClass == .nonIdempotent {
                    attempt.status = .unresolved
                } else {
                    attempt.status = .startedUnknown
                }
                try await attemptStore.saveAttempt(attempt)

                let obs = Observation(
                    actionID: proposal.actionID,
                    summary: "Execution side effect threw error: \(error)",
                    succeeded: false
                )
                return (obs, attempt)
            }
        }

        // Proposals without a toolID complete directly
        attempt.status = .completed
        attempt.completedAt = Date()
        try await attemptStore.saveAttempt(attempt)
        let obs = Observation(actionID: proposal.actionID, summary: "Executed proposal (no tool)", succeeded: true)
        return (obs, attempt)
    }

    public func resolveEvidence(
        attempt: ExecutionAttempt
    ) async -> EvidenceResolution {
        guard let toolID = attempt.toolID else {
            return .unavailable
        }
        guard let cap = targetCapability(for: toolID) else {
            // Missing target capability -> fail closed as .unavailable
            return .unavailable
        }
        guard cap.supportsEvidenceResolution else {
            // Target does NOT support evidence resolution: global resolver MUST NOT be queried!
            return .unavailable
        }

        if let resolver = evidenceResolver {
            do {
                let res = try await resolver.resolve(
                    attemptID: attempt.attemptID,
                    idempotencyKey: attempt.idempotencyKey
                )
                if res != .unavailable {
                    return res
                }
            } catch {
                return .unavailable
            }
        }

        do {
            if let receipt = try await attemptStore.receipt(forAttemptID: attempt.attemptID) {
                return .completed(receipt)
            }
        } catch {
            return .unavailable
        }

        return .unavailable
    }
}
