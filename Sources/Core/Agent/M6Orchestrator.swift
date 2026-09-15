import Foundation
import PAFoundation
import PAPolicy
import PACognition
import PAAgency
import PAModules
import PAMemory
import PAProviders
import PAObservability
import PAEvents

/// Coordinates the complete normative M6 flow:
/// Perception → Context → Reasoning → Planning → ActionProposal → Verification → Policy Authorization → Execution → Observation → Evaluation → Reflection → StateUpdate → Continue / Complete / Abort
public actor M6Orchestrator: Sendable {
    private let runtime: AgentRuntime
    private let policy: any PolicyEvaluating
    private let approvalGate: (any ApprovalGate)?
    private let logger: any AgentLogger
    private let eventLog: any EventLog
    private let maxCycles: Int

    public init(
        runtime: AgentRuntime,
        policy: any PolicyEvaluating,
        approvalGate: (any ApprovalGate)? = nil,
        logger: any AgentLogger = NullLoggerBridge(),
        eventLog: any EventLog,
        maxCycles: Int = 5
    ) {
        self.runtime = runtime
        self.policy = policy
        self.approvalGate = approvalGate
        self.logger = logger
        self.eventLog = eventLog
        self.maxCycles = maxCycles
    }

    /// Default cognitive process implementation if custom CognitionPipelining is not provided.
    public func processCognition(perception: Perception, goalID: GoalID) async throws -> CognitionOutput {
        let traceID = runtime.sessionTrace
        await emitEvent(kind: .contextBuilt, payload: ["rawInput": perception.rawInput, "source": perception.source], traceID: traceID)

        let plan = Plan(
            id: PlanID(),
            goalID: goalID,
            steps: [
                PlanStep(index: 0, description: perception.rawInput, skillID: nil)
            ]
        )
        await emitEvent(kind: .planProduced, payload: ["planID": plan.id.rawValue, "goalID": goalID.rawValue], traceID: traceID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: plan.id,
            toolID: ToolID(rawValue: perception.rawInput),
            description: perception.rawInput,
            capabilities: .read
        )
        await emitEvent(kind: .actionProposed, payload: ["actionID": proposal.actionID.rawValue, "planID": plan.id.rawValue], traceID: traceID)

        let verification = VerificationResult(accepted: true, notes: "Verified proposal")
        await emitEvent(kind: .verificationCompleted, payload: ["accepted": String(verification.accepted), "notes": verification.notes], traceID: traceID)

        return CognitionOutput(plan: plan, proposals: [proposal], verification: verification)
    }

    /// Execute Agency execution loop: Policy Authorization -> Execution -> Observation -> Evaluation
    public func executeAgency(
        output: CognitionOutput,
        authorizer: any ActionAuthorizing = DefaultActionAuthorizer()
    ) async throws -> CognitionFeedback {
        let traceID = runtime.sessionTrace

        // Verification rejection check
        guard output.verification.accepted else {
            await emitEvent(
                kind: .verificationCompleted,
                payload: ["accepted": "false", "notes": output.verification.notes],
                traceID: traceID
            )
            let eval = Evaluation(
                goalID: output.plan.goalID,
                disposition: .abort,
                reason: "Verification rejected proposal: \(output.verification.notes)"
            )
            return CognitionFeedback(observations: [], evaluation: eval)
        }

        var observations: [Observation] = []
        for proposal in output.proposals {
            await emitEvent(
                kind: .actionProposed,
                payload: ["actionID": proposal.actionID.rawValue, "description": proposal.description],
                traceID: traceID
            )

            // Step: Policy Authorization
            if approvalGate != nil {
                await emitEvent(
                    kind: .approvalRequested,
                    payload: ["actionID": proposal.actionID.rawValue],
                    traceID: traceID
                )
            }

            guard let intent = try await authorizer.authorize(
                proposal: proposal,
                policy: policy,
                gate: approvalGate
            ) else {
                if approvalGate != nil {
                    await emitEvent(
                        kind: .approvalResolved,
                        payload: ["actionID": proposal.actionID.rawValue, "approved": "false"],
                        traceID: traceID
                    )
                }
                await emitEvent(
                    kind: .failed,
                    payload: ["actionID": proposal.actionID.rawValue, "reason": "Policy denied or approval failed"],
                    traceID: traceID
                )
                observations.append(Observation(
                    actionID: proposal.actionID,
                    summary: "Policy denied or approval failed for action \(proposal.actionID.rawValue)",
                    succeeded: false
                ))
                continue
            }

            if approvalGate != nil {
                await emitEvent(
                    kind: .approvalResolved,
                    payload: ["actionID": proposal.actionID.rawValue, "approved": "true"],
                    traceID: traceID
                )
            }

            // Step: Execution & Observation
            let moduleExecutor = runtime.coordination.modules
            let succeeded: Bool
            let summary: String

            if let toolID = intent.toolID, let executor = moduleExecutor {
                await emitEvent(
                    kind: .toolCalled,
                    payload: ["toolID": toolID.rawValue, "actionID": proposal.actionID.rawValue],
                    traceID: traceID
                )

                let schemaIdentifier: String
                if toolID.rawValue.hasPrefix("mod.") || toolID.rawValue.hasPrefix("tool.") {
                    schemaIdentifier = "\(toolID.rawValue).in"
                } else {
                    schemaIdentifier = "mod.\(toolID.rawValue).in"
                }

                let schema = SchemaDocument(identifier: schemaIdentifier)
                let invocation = ModuleInvocation(
                    moduleID: ModuleID(rawValue: toolID.rawValue),
                    input: ModulePayload(schema: schema, fields: ["input": proposal.description, "message": proposal.description, "text": proposal.description])
                )
                do {
                    let result = try await executor.execute(invocation)
                    succeeded = (result.state == ModuleExecutionState.completed)
                    if succeeded {
                        summary = result.output.fields["message"] ?? result.output.fields["output"] ?? result.output.fields["text"] ?? "Executed module \(toolID.rawValue)"
                    } else {
                        summary = "Module execution failed with state \(result.state.rawValue)"
                    }
                } catch {
                    succeeded = false
                    summary = "Module execution failed for \(toolID.rawValue): \(error)"
                    await emitEvent(
                        kind: .failed,
                        payload: ["actionID": proposal.actionID.rawValue, "toolID": toolID.rawValue, "error": String(describing: error)],
                        traceID: traceID
                    )
                }
            } else {
                // Unknown/missing moduleExecutor or missing toolID -> fail closed
                succeeded = false
                if intent.toolID == nil {
                    summary = "Action failed closed: no explicit toolID provided in ActionProposal/ActionIntent"
                } else {
                    summary = "Action failed closed: module executor unavailable"
                }
                await emitEvent(
                    kind: .failed,
                    payload: ["actionID": proposal.actionID.rawValue, "reason": summary],
                    traceID: traceID
                )
            }

            observations.append(Observation(actionID: proposal.actionID, summary: summary, succeeded: succeeded))
        }

        let disposition: AgencyDisposition
        let reason: String

        if output.proposals.isEmpty {
            disposition = .abort
            reason = "Zero proposals generated; cannot complete execution successfully"
        } else if observations.allSatisfy({ $0.succeeded }) {
            disposition = .complete
            reason = "All actions executed successfully"
        } else if observations.allSatisfy({ !$0.succeeded }) {
            disposition = .abort
            reason = "All actions failed policy authorization or execution"
        } else {
            disposition = .continue
            reason = "Partial action execution failures encountered"
        }

        let eval = Evaluation(
            goalID: output.plan.goalID,
            disposition: disposition,
            reason: reason
        )

        return CognitionFeedback(observations: observations, evaluation: eval)
    }

    /// Runs complete M6 normative cycles until complete/abort or maxCycles reached.
    public func runCycle(
        perception: Perception,
        goalID: GoalID,
        customCognition: (any CognitionPipelining)? = nil,
        customAgency: (any AgencyLooping)? = nil
    ) async throws -> AgencyDisposition {
        var currentPerception = perception
        var cycleCount = 0

        while cycleCount < maxCycles {
            cycleCount += 1

            // 1. Cognition: Perception → Context → Reasoning → Planning → ActionProposal → Verification
            let output: CognitionOutput
            if let customCognition {
                output = try await customCognition.process(perception: currentPerception, goalID: goalID)
            } else {
                output = try await processCognition(perception: currentPerception, goalID: goalID)
            }

            // 2. Agency: Policy Authorization → Execution → Observation → Evaluation
            let feedback: CognitionFeedback
            if let customAgency {
                feedback = try await customAgency.executePlan(
                    output: output,
                    policy: policy,
                    gate: approvalGate,
                    moduleExecutor: runtime.coordination.modules
                )
            } else {
                feedback = try await executeAgency(output: output)
            }

            // 3. Post-execution Reflection
            let reflection: Reflection
            if let customCognition {
                reflection = try await customCognition.reflect(feedback: feedback)
            } else {
                reflection = Reflection(
                    notes: "Executed \(feedback.observations.count) actions for goal \(goalID.rawValue). Evaluation: \(feedback.evaluation.reason)",
                    shouldAdapt: feedback.evaluation.disposition == .continue
                )
            }

            // 4. StateUpdate request -> Authoritative AgentRuntime / PAMemory
            let stateUpdate = StateUpdate(
                goalID: goalID,
                memoryRecordsToCapture: [],
                reflection: reflection
            )
            try await runtime.applyStateUpdate(stateUpdate)

            // 5. Terminal / Cycle Decision via AgentRuntime
            switch feedback.evaluation.disposition {
            case .complete:
                try await runtime.complete(goalID: goalID)
                return .complete
            case .abort:
                try await runtime.abort(goalID: goalID)
                return .abort
            case .continue:
                // Re-enter defined Cognition cycle with post-execution feedback
                currentPerception = Perception(
                    rawInput: reflection.notes,
                    source: "feedback"
                )
                continue
            }
        }

        // Max cycles exceeded without resolution -> fail closed by aborting
        try await runtime.abort(goalID: goalID)
        return .abort
    }

    private func emitEvent(kind: ExecutionEventKind, payload: [String: String], traceID: TraceID) async {
        let event = ExecutionEvent(
            traceID: traceID,
            kind: kind,
            timestamp: Date(),
            payload: payload
        )
        try? await eventLog.append(event)
    }
}
