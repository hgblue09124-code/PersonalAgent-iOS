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

    public init(
        runtime: AgentRuntime,
        policy: any PolicyEvaluating,
        approvalGate: (any ApprovalGate)? = nil,
        logger: any AgentLogger = NullLoggerBridge(),
        eventLog: any EventLog
    ) {
        self.runtime = runtime
        self.policy = policy
        self.approvalGate = approvalGate
        self.logger = logger
        self.eventLog = eventLog
    }

    /// Default cognitive process implementation if custom CognitionPipelining is not provided.
    public func processCognition(perception: Perception, goalID: GoalID) async throws -> CognitionOutput {
        let plan = Plan(
            id: PlanID(),
            goalID: goalID,
            steps: [
                PlanStep(index: 0, description: perception.rawInput, skillID: nil)
            ]
        )

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: plan.id,
            toolID: ToolID(rawValue: perception.rawInput),
            description: perception.rawInput,
            capabilities: .read
        )

        let verification = VerificationResult(accepted: true, notes: "Verified proposal")
        return CognitionOutput(plan: plan, proposals: [proposal], verification: verification)
    }

    /// Execute Agency execution loop: Policy Authorization -> Execution -> Observation -> Evaluation
    public func executeAgency(
        output: CognitionOutput,
        authorizer: any ActionAuthorizing = DefaultActionAuthorizer()
    ) async throws -> CognitionFeedback {
        // Verification rejection check
        guard output.verification.accepted else {
            let eval = Evaluation(
                goalID: output.plan.goalID,
                disposition: .abort,
                reason: "Verification rejected proposal: \(output.verification.notes)"
            )
            return CognitionFeedback(observations: [], evaluation: eval)
        }

        var observations: [Observation] = []
        for proposal in output.proposals {
            // Step: Policy Authorization
            guard let intent = try await authorizer.authorize(
                proposal: proposal,
                policy: policy,
                gate: approvalGate
            ) else {
                // Policy denial or approval failure
                observations.append(Observation(actionID: proposal.actionID, summary: "Policy denied or approval failed", succeeded: false))
                continue
            }

            // Step: Execution & Observation
            let moduleExecutor = runtime.coordination.modules
            let succeeded: Bool
            let summary: String
            if let toolID = intent.toolID {
                if let executor = moduleExecutor {
                    let candidates = [
                        ModuleID(rawValue: toolID.rawValue),
                        ModuleID(rawValue: "tool." + toolID.rawValue)
                    ]

                    var executionResult: ModuleResult?
                    var lastError: Error?

                    for candidate in candidates {
                        let schema = SchemaDocument(identifier: candidate.rawValue.hasPrefix("tool.") ? "tool.\(toolID.rawValue).in" : "mod.\(toolID.rawValue).in")
                        let payload = ModulePayload(
                            schema: schema,
                            fields: [
                                "input": proposal.description,
                                "message": proposal.description,
                                "arguments": proposal.description,
                                "text": proposal.description,
                                "must": proposal.description
                            ]
                        )
                        do {
                            let res = try await executor.execute(ModuleInvocation(moduleID: candidate, input: payload))
                            executionResult = res
                            break
                        } catch {
                            lastError = error
                            continue
                        }
                    }

                    if let result = executionResult {
                        succeeded = (result.state == ModuleExecutionState.completed)
                        summary = result.output.fields["message"] ?? result.output.fields["output"] ?? result.output.fields["text"] ?? "Executed module \(toolID.rawValue)"
                    } else {
                        // Fail closed: execution error or missing module
                        succeeded = false
                        if let err = lastError {
                            summary = "Execution error: \(err)"
                        } else {
                            summary = "Missing module executor for target \(toolID.rawValue)"
                        }
                    }
                } else {
                    // Fail closed: missing executor produces failed observation
                    succeeded = false
                    summary = "Missing module executor for target \(toolID.rawValue)"
                }
            } else {
                succeeded = true
                summary = "Executed intent: \(intent.summary)"
            }

            observations.append(Observation(actionID: proposal.actionID, summary: summary, succeeded: succeeded))
        }

        let allSucceeded = !observations.isEmpty && observations.allSatisfy { $0.succeeded }
        let eval = Evaluation(
            goalID: output.plan.goalID,
            disposition: allSucceeded ? .complete : (observations.isEmpty ? .abort : .continue),
            reason: allSucceeded ? "All actions executed successfully" : "Execution completed with partial/failed observations"
        )

        return CognitionFeedback(observations: observations, evaluation: eval)
    }

    /// Runs one complete M6 normative cycle.
    public func runCycle(
        perception: Perception,
        goalID: GoalID,
        customCognition: (any CognitionPipelining)? = nil,
        customAgency: (any AgencyLooping)? = nil,
        maxCycles: Int = 5
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
                    notes: "Executed \(feedback.observations.count) actions for goal \(goalID.rawValue)",
                    shouldAdapt: feedback.evaluation.disposition == AgencyDisposition.continue
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
                // Re-enter Cognition loop with feedback as perception input
                currentPerception = Perception(
                    rawInput: "Continuation cycle \(cycleCount + 1) based on feedback: \(feedback.evaluation.reason)",
                    source: "feedback"
                )
            }
        }

        // Bounded retry exceeded: abort fail-closed
        try await runtime.abort(goalID: goalID)
        return .abort
    }
}
