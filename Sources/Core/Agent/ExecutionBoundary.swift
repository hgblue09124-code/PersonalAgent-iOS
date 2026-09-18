import Foundation
import PAFoundation
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PAEvents

public actor ExecutionBoundary {
    private let attemptStore: any ExecutionAttemptStore
    private let policy: any PolicyEvaluating
    private let approvalGate: (any ApprovalGate)?
    private let moduleRuntime: ModuleRuntime?
    private let evidenceResolver: (any ExecutionEvidenceResolver)?
    private let eventLog: any EventLog

    public init(
        attemptStore: any ExecutionAttemptStore,
        policy: any PolicyEvaluating = DefaultPolicyEvaluator(),
        approvalGate: (any ApprovalGate)? = nil,
        moduleRuntime: ModuleRuntime? = nil,
        evidenceResolver: (any ExecutionEvidenceResolver)? = nil,
        eventLog: any EventLog = InMemoryEventLog()
    ) {
        self.attemptStore = attemptStore
        self.policy = policy
        self.approvalGate = approvalGate
        self.moduleRuntime = moduleRuntime
        self.evidenceResolver = evidenceResolver
        self.eventLog = eventLog
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

        // 1. Policy & Lease check
        let intent = ActionIntent(
            actionID: proposal.actionID,
            toolID: proposal.toolID,
            capabilities: proposal.capabilities,
            summary: proposal.description
        )

        let decision = await policy.evaluate(intent)
        var allowed = decision.allowed

        if decision.requiresApproval, let gate = approvalGate {
            allowed = try await gate.requestApproval(for: intent)
        }

        if !allowed {
            let attempt = ExecutionAttempt(
                runID: runID,
                actionID: proposal.actionID,
                toolID: proposal.toolID,
                idempotencyKey: idempotencyKey,
                status: .failed,
                startedAt: Date(),
                completedAt: Date()
            )
            try await attemptStore.saveAttempt(attempt)
            let obs = Observation(
                actionID: proposal.actionID,
                summary: "Denied by policy: \(decision.reason)",
                succeeded: false
            )
            return (obs, attempt)
        }

        // Consume step atomically
        try await lease.consume(step: 1, forRunID: runID)

        // 2. Initialize attempt as NOT_STARTED on disk
        var attempt = ExecutionAttempt(
            runID: runID,
            actionID: proposal.actionID,
            toolID: proposal.toolID,
            idempotencyKey: idempotencyKey,
            status: .notStarted
        )
        try await attemptStore.saveAttempt(attempt)

        // 3. Mark attempt as STARTED_UNKNOWN immediately prior to dispatch
        attempt.status = .startedUnknown
        attempt.startedAt = Date()
        try await attemptStore.saveAttempt(attempt)

        // 4. Dispatch side effect
        var obsSummary = "Executed proposal"
        var succeeded = true
        var rawFields: [String: String] = [:]

        if let toolID = proposal.toolID {
            guard let modules = moduleRuntime else {
                obsSummary = "Execution target unavailable: moduleRuntime is missing for tool '\(toolID.rawValue)'"
                succeeded = false
                attempt.status = .failed
                attempt.completedAt = Date()
                try await attemptStore.saveAttempt(attempt)
                let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                return (obs, attempt)
            }

            let contracts = await modules.contracts()
            guard let targetContract = contracts.first(where: { $0.id.rawValue == toolID.rawValue }) else {
                obsSummary = "Execution target unavailable: tool '\(toolID.rawValue)' not registered in ModuleCatalog"
                succeeded = false
                attempt.status = .failed
                attempt.completedAt = Date()
                try await attemptStore.saveAttempt(attempt)
                let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
                return (obs, attempt)
            }

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
                obsSummary = res.output.fields["output"] ?? res.output.fields["result"] ?? res.output.fields["message"] ?? res.output.fields["text"] ?? "Success"
                succeeded = (res.state == .completed)
                rawFields = res.output.fields
            } catch {
                // Dispatch threw or failed. Status remains STARTED_UNKNOWN on disk per M7 invariants!
                // Exception does NOT directly mean FAILED.
                let obs = Observation(
                    actionID: proposal.actionID,
                    summary: "Execution side effect threw error: \(error)",
                    succeeded: false
                )
                return (obs, attempt)
            }
        }

        if succeeded {
            attempt.status = .completed
            attempt.completedAt = Date()

            if let toolID = proposal.toolID {
                let receipt = ExecutionReceipt(
                    attemptID: attempt.attemptID,
                    toolID: toolID,
                    idempotencyKey: idempotencyKey,
                    timestamp: Date(),
                    outputSummary: obsSummary,
                    rawOutputFields: rawFields
                )
                try await attemptStore.saveReceipt(receipt)
                attempt.receiptRef = receipt.receiptID
            }

            try await attemptStore.saveAttempt(attempt)
            let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: true)
            return (obs, attempt)
        } else {
            attempt.status = .failed
            attempt.completedAt = Date()
            try await attemptStore.saveAttempt(attempt)
            let obs = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: false)
            return (obs, attempt)
        }
    }

    public func resolveEvidence(
        attempt: ExecutionAttempt
    ) async -> EvidenceResolution {
        guard let resolver = evidenceResolver else {
            return .unavailable
        }
        do {
            return try await resolver.resolve(
                attemptID: attempt.attemptID,
                idempotencyKey: attempt.idempotencyKey
            )
        } catch {
            // Resolver invocation error MUST be mapped to unavailable per M7.0 semantics
            return .unavailable
        }
    }
}
