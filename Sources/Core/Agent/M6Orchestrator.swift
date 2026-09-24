import Foundation
import PAFoundation
import PAObservability
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PAProviders

public enum AgentExecutionProgress: Sendable, Equatable {
    case perception
    case reasoning
    case reasoningCompleted(String)
    case planning
    case actionProposed(String)
    case verification
    case executing
    case observation(String)
    case evaluating
    case completed(String)
    case failed(String)

    public var title: String {
        switch self {
        case .perception: return "Receiving task"
        case .reasoning: return "Thinking"
        case .reasoningCompleted: return "Reasoning ready"
        case .planning: return "Planning"
        case .actionProposed: return "Action proposed"
        case .verification: return "Verifying"
        case .executing: return "Executing"
        case .observation: return "Observing"
        case .evaluating: return "Evaluating"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var detail: String {
        switch self {
        case .perception: return "Reading your task…"
        case .reasoning: return "Local model is generating a decision…"
        case .reasoningCompleted(let text): return text
        case .planning: return "Building the next action…"
        case .actionProposed(let text): return text
        case .verification: return "Checking the proposed action…"
        case .executing: return "Running the selected action…"
        case .observation(let text): return text
        case .evaluating: return "Evaluating the execution result…"
        case .completed(let text): return text
        case .failed(let text): return text
        }
    }
}

public protocol ContextAssembling: Sendable {
    func assembleContext(
        perception: Perception,
        observations: [Observation],
        evaluation: Evaluation?
    ) async throws -> ContextBundle
}

public protocol Reasoning: Sendable {
    func reason(context: ContextBundle) async throws -> ReasoningResult
}

public protocol Verifying: Sendable {
    func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult
}

public protocol Evaluating: Sendable {
    func evaluate(goalID: GoalID, observations: [Observation]) async throws -> Evaluation
}

public protocol Reflecting: Sendable {
    func reflect(goalID: GoalID, observations: [Observation], evaluation: Evaluation) async throws -> Reflection
}

public struct DefaultContextAssembler: ContextAssembling {
    public init() {}
    public func assembleContext(
        perception: Perception,
        observations: [Observation] = [],
        evaluation: Evaluation? = nil
    ) async throws -> ContextBundle {
        ContextBundle(perception: perception, memoryIDs: [], skillIDs: [])
    }
}

public struct LLMReasoner: Reasoning {
    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    public func reason(context: ContextBundle) async throws -> ReasoningResult {
        let prompt = """
        You are the reasoning component of a personal agent.
        Return a concise plan/decision for the user's task.
        Do not claim an action was executed.
        
        User task:
        \(context.perception.rawInput)
        """

        let response = try await provider.complete(
            LLMRequest(
                model: provider.identity.models.first?.id ?? ModelID(rawValue: "local"),
                prompt: prompt
            )
        )

        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw KernelError.invalidStateUpdate("LLM reasoning returned empty output")
        }

        return ReasoningResult(
            summary: text,
            providerID: provider.identity.id,
            modelID: nil
        )
    }
}

public struct DefaultReasoner: Reasoning {
    public init() {}
    public func reason(context: ContextBundle) async throws -> ReasoningResult {
        ReasoningResult(summary: "Reasoned for \(context.perception.rawInput)", providerID: nil, modelID: nil)
    }
}

public struct DefaultPlanner: Planning {
    public init() {}
    public func plan(goalID: GoalID, context: ContextBundle, reasoning: ReasoningResult) async throws -> Plan {
        let step = PlanStep(index: 0, description: context.perception.rawInput, skillID: nil)
        return Plan(goalID: goalID, steps: [step])
    }
}

public struct DefaultProposer: Executing {
    public init() {}
    public func propose(plan: Plan) async throws -> [ActionProposal] {
        plan.steps.map { step in
            ActionProposal(
                planID: plan.id,
                description: step.description,
                capabilities: .read
            )
        }
    }
}

public struct DefaultVerifier: Verifying {
    public init() {}
    public func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult {
        VerificationResult(accepted: true, notes: "Verified default plan")
    }
}

public struct DefaultPolicyEvaluator: PolicyEvaluating {
    public init() {}
    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .allow("Default policy permit")
    }
}

public struct DefaultEvaluator: Evaluating {
    public init() {}
    public func evaluate(goalID: GoalID, observations: [Observation]) async throws -> Evaluation {
        let allSucceeded = !observations.isEmpty && observations.allSatisfy(\.succeeded)
        let disposition: AgencyDisposition = allSucceeded ? .complete : .abort
        return Evaluation(
            goalID: goalID,
            disposition: disposition,
            reason: allSucceeded ? "All actions succeeded" : "Execution failed"
        )
    }
}

public struct DefaultReflector: Reflecting {
    public init() {}
    public func reflect(goalID: GoalID, observations: [Observation], evaluation: Evaluation) async throws -> Reflection {
        Reflection(
            notes: "Reflected on evaluation: \(evaluation.reason)",
            shouldAdapt: evaluation.disposition == .continue
        )
    }
}

/// M6 Orchestrator coordinates Cognition, Policy, Agency, and Kernel state according to Documentation/M6.md.
public actor M6Orchestrator {
    private let runtime: AgentRuntime
    private let eventLog: any EventLog
    private let logger: any AgentLogger
    private let contextAssembler: any ContextAssembling
    private let reasoner: any Reasoning
    private let planner: any Planning
    private let proposer: any Executing
    private let verifier: any Verifying
    private let policy: any PolicyEvaluating
    private let approvalGate: (any ApprovalGate)?
    private let moduleRuntime: ModuleRuntime?
    private let evaluator: any Evaluating
    private let reflector: any Reflecting
    private let maxCycles: Int

    public init(
        runtime: AgentRuntime,
        eventLog: any EventLog,
        logger: any AgentLogger = NullLoggerBridge(),
        contextAssembler: (any ContextAssembling)? = nil,
        reasoner: (any Reasoning)? = nil,
        planner: (any Planning)? = nil,
        proposer: (any Executing)? = nil,
        verifier: (any Verifying)? = nil,
        policy: (any PolicyEvaluating)? = nil,
        approvalGate: (any ApprovalGate)? = nil,
        moduleRuntime: ModuleRuntime? = nil,
        evaluator: (any Evaluating)? = nil,
        reflector: (any Reflecting)? = nil,
        maxCycles: Int = 3
    ) {
        self.runtime = runtime
        self.eventLog = eventLog
        self.logger = logger
        self.contextAssembler = contextAssembler ?? DefaultContextAssembler()
        self.reasoner = reasoner ?? DefaultReasoner()
        self.planner = planner ?? DefaultPlanner()
        self.proposer = proposer ?? DefaultProposer()
        self.verifier = verifier ?? DefaultVerifier()
        self.policy = policy ?? DefaultPolicyEvaluator()
        self.approvalGate = approvalGate
        self.moduleRuntime = moduleRuntime
        self.evaluator = evaluator ?? DefaultEvaluator()
        self.reflector = reflector ?? DefaultReflector()
        self.maxCycles = maxCycles
    }

    public func run(goalID: GoalID, rawInput: String? = nil, progress: (@Sendable (AgentExecutionProgress) -> Void)? = nil) async throws -> Evaluation {
        let traceID = TraceID()
        if await runtime.currentState().lifecycle == .created {
            try await runtime.start()
        }

        guard let goal = await runtime.goal(id: goalID) else {
            throw KernelError.goalNotFound(goalID)
        }

        // Activate goal if proposed
        if goal.status == .proposed {
            try await runtime.activate(goalID: goalID)
        }

        let input = rawInput ?? goal.statement
        var cycleCount = 0
        var finalEvaluation: Evaluation?
        var previousObservations: [Observation] = []
        var previousEvaluation: Evaluation? = nil

        while cycleCount < maxCycles {
            cycleCount += 1
            let perception = Perception(rawInput: input, source: "user")

            progress?(.perception)

            // 1. Perception
            try await emit(
                traceID: traceID,
                kind: .perceptionReceived,
                payload: ["goalID": goalID.rawValue, "rawInput": perception.rawInput]
            )

            // 2. Context with feedback from previous cycles
            let context = try await contextAssembler.assembleContext(
                perception: perception,
                observations: previousObservations,
                evaluation: previousEvaluation
            )
            try await emit(
                traceID: traceID,
                kind: .contextBuilt,
                payload: ["goalID": goalID.rawValue, "memoryIDsCount": "\(context.memoryIDs.count)"]
            )

            // 3. Reasoning
            let reasoningResult = try await reasoner.reason(context: context)

            // 4. Planning
            let plan = try await planner.plan(goalID: goalID, context: context, reasoning: reasoningResult)
            try await emit(
                traceID: traceID,
                kind: .planProduced,
                payload: ["goalID": goalID.rawValue, "planID": plan.id.rawValue, "stepCount": "\(plan.steps.count)"]
            )

            // 5. ActionProposals
            let proposals = try await proposer.propose(plan: plan)
            for proposal in proposals {
                var payload: [String: String] = [
                    "goalID": goalID.rawValue,
                    "planID": proposal.planID.rawValue,
                    "actionID": proposal.actionID.rawValue,
                    "description": proposal.description,
                ]
                if let toolID = proposal.toolID {
                    payload["toolID"] = toolID.rawValue
                }
                try await emit(traceID: traceID, kind: .actionProposed, payload: payload)
            }

            // 6. Verification
            let verification = try await verifier.verify(plan: plan, proposals: proposals)
            try await emit(
                traceID: traceID,
                kind: .verificationCompleted,
                payload: [
                    "goalID": goalID.rawValue,
                    "planID": plan.id.rawValue,
                    "accepted": "\(verification.accepted)",
                    "notes": verification.notes,
                ]
            )

            if !verification.accepted {
                let obs = proposals.map { Observation(actionID: $0.actionID, summary: "Verification rejected: \(verification.notes)", succeeded: false) }
                let eval = Evaluation(goalID: goalID, disposition: .abort, reason: "Verification rejected")
                let refl = try await reflector.reflect(goalID: goalID, observations: obs, evaluation: eval)

                let stateUpdate = StateUpdate(
                    goalID: goalID,
                    targetStatus: .aborted,
                    evidence: [
                        "disposition": eval.disposition.rawValue,
                        "reason": eval.reason,
                        "reflection": refl.notes,
                    ]
                )
                try await runtime.applyStateUpdate(stateUpdate)
                return eval
            }

            // 7. Policy Authorization & Execution
            var observations: [Observation] = []
            for proposal in proposals {
                let intent = ActionIntent(
                    actionID: proposal.actionID,
                    toolID: proposal.toolID,
                    capabilities: proposal.capabilities,
                    summary: proposal.description
                )

                let decision = await policy.evaluate(intent)
                var allowed = decision.allowed

                if decision.requiresApproval, let gate = approvalGate {
                    try await emit(
                        traceID: traceID,
                        kind: .approvalRequested,
                        payload: ["goalID": goalID.rawValue, "actionID": proposal.actionID.rawValue]
                    )
                    allowed = try await gate.requestApproval(for: intent)
                    try await emit(
                        traceID: traceID,
                        kind: .approvalResolved,
                        payload: ["goalID": goalID.rawValue, "actionID": proposal.actionID.rawValue, "approved": "\(allowed)"]
                    )
                }

                if !allowed {
                    var payload: [String: String] = [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "reason": decision.reason,
                    ]
                    if let toolID = intent.toolID {
                        payload["toolID"] = toolID.rawValue
                    }
                    try await emit(traceID: traceID, kind: .actionDenied, payload: payload)
                    observations.append(Observation(actionID: proposal.actionID, summary: "Denied by policy: \(decision.reason)", succeeded: false))
                    continue
                }

                var authPayload: [String: String] = [
                    "goalID": goalID.rawValue,
                    "actionID": proposal.actionID.rawValue,
                    "reason": decision.reason,
                ]
                if let toolID = intent.toolID {
                    authPayload["toolID"] = toolID.rawValue
                }
                try await emit(traceID: traceID, kind: .actionAuthorized, payload: authPayload)

                // Execute action
                let obs = try await executeProposal(proposal, traceID: traceID, goalID: goalID)
                observations.append(obs)
            }

            // 8. Evaluation
            let evaluation = try await evaluator.evaluate(goalID: goalID, observations: observations)
            try await emit(
                traceID: traceID,
                kind: .evaluationCompleted,
                payload: [
                    "goalID": goalID.rawValue,
                    "disposition": evaluation.disposition.rawValue,
                    "reason": evaluation.reason,
                ]
            )

            // 9. Reflection (Post-Execution)
            let reflection = try await reflector.reflect(goalID: goalID, observations: observations, evaluation: evaluation)
            try await emit(
                traceID: traceID,
                kind: .reflectionCompleted,
                payload: [
                    "goalID": goalID.rawValue,
                    "notes": reflection.notes,
                    "shouldAdapt": "\(reflection.shouldAdapt)",
                ]
            )

            // 10. Authoritative StateUpdate
            let targetGoalStatus: GoalStatus
            switch evaluation.disposition {
            case .complete:
                targetGoalStatus = .completed
            case .abort:
                targetGoalStatus = .aborted
            case .continue:
                targetGoalStatus = .active
            }

            let stateUpdate = StateUpdate(
                goalID: goalID,
                targetStatus: targetGoalStatus,
                evidence: [
                    "disposition": evaluation.disposition.rawValue,
                    "reason": evaluation.reason,
                    "reflection": reflection.notes,
                    "observationIDs": observations.map(\.actionID.rawValue).joined(separator: ","),
                ]
            )

            try await runtime.applyStateUpdate(stateUpdate)

            finalEvaluation = evaluation
            previousObservations = observations
            previousEvaluation = evaluation

            if evaluation.disposition != .continue {
                break
            }
        }

        guard let result = finalEvaluation else {
            throw KernelError.invalidStateUpdate("M6 cycle did not produce an evaluation")
        }
        return result
    }

    private func executeProposal(_ proposal: ActionProposal, traceID: TraceID, goalID: GoalID) async throws -> Observation {
        var obsSummary = "Executed proposal"
        var succeeded = true

        if let toolID = proposal.toolID {
            guard let modules = moduleRuntime else {
                let obs = Observation(
                    actionID: proposal.actionID,
                    summary: "Execution target unavailable: moduleRuntime is missing for tool '\(toolID.rawValue)'",
                    succeeded: false
                )
                let obsPayload: [String: String] = [
                    "goalID": goalID.rawValue,
                    "actionID": proposal.actionID.rawValue,
                    "toolID": toolID.rawValue,
                    "summary": obs.summary,
                    "succeeded": "false",
                ]
                try await emit(traceID: traceID, kind: .observationProduced, payload: obsPayload)
                return obs
            }

            let contracts = await modules.contracts()
            guard let targetContract = contracts.first(where: { $0.id.rawValue == toolID.rawValue }) else {
                let obs = Observation(
                    actionID: proposal.actionID,
                    summary: "Execution target unavailable: tool '\(toolID.rawValue)' not registered in ModuleCatalog",
                    succeeded: false
                )
                let obsPayload: [String: String] = [
                    "goalID": goalID.rawValue,
                    "actionID": proposal.actionID.rawValue,
                    "toolID": toolID.rawValue,
                    "summary": obs.summary,
                    "succeeded": "false",
                ]
                try await emit(traceID: traceID, kind: .observationProduced, payload: obsPayload)
                return obs
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
            } catch {
                obsSummary = "Module execution failed: \(error)"
                succeeded = false
            }
        }

        // Emit actionExecuted after actual execution attempt
        var execPayload: [String: String] = [
            "goalID": goalID.rawValue,
            "actionID": proposal.actionID.rawValue,
            "description": proposal.description,
            "succeeded": "\(succeeded)",
        ]
        if let toolID = proposal.toolID {
            execPayload["toolID"] = toolID.rawValue
        }
        try await emit(traceID: traceID, kind: .actionExecuted, payload: execPayload)

        let observation = Observation(actionID: proposal.actionID, summary: obsSummary, succeeded: succeeded)
        var obsPayload: [String: String] = [
            "goalID": goalID.rawValue,
            "actionID": proposal.actionID.rawValue,
            "summary": observation.summary,
            "succeeded": "\(observation.succeeded)",
        ]
        if let toolID = proposal.toolID {
            obsPayload["toolID"] = toolID.rawValue
        }
        try await emit(traceID: traceID, kind: .observationProduced, payload: obsPayload)

        return observation
    }

    private func emit(traceID: TraceID, kind: ExecutionEventKind, payload: [String: String]) async throws {
        let event = ExecutionEvent(
            traceID: traceID,
            kind: kind,
            timestamp: Date(),
            payload: payload
        )
        logger.log(LogEvent(level: .info, category: "m6.orchestrator", message: kind.rawValue, metadata: payload))
        try await eventLog.append(event)
    }
}
