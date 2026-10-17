import Foundation
import PAKernel
import PAObservability
import PAEvents
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

public protocol Evaluating: Sendable {
    func evaluate(goalID: GoalID, observations: [Observation]) async throws -> Evaluation
}

public protocol Reflecting: Sendable {
    func reflect(goalID: GoalID, observations: [Observation], evaluation: Evaluation) async throws -> Reflection
}

/// Runtime-facing seam for Skill discovery, selection, authorization-aware execution, and verification.
public struct SkillExecutionReceipt: Sendable, Equatable {
    public let skillID: SkillID
    public let output: String
    public let verified: Bool
    public init(skillID: SkillID, output: String, verified: Bool) {
        self.skillID = skillID
        self.output = output
        self.verified = verified
    }
}

public protocol SkillExecutionBoundary: Sendable {
    func discoverSkillIDs() async throws -> [SkillID]
    func selectSkill(goalStatement: String, availableSkillIDs: [SkillID]) async throws -> SkillID?
    func requiredCapabilities(for skillID: SkillID) async throws -> CapabilityLevel
    func execute(skillID: SkillID, input: String, authorizedCapabilities: CapabilityLevel) async throws -> SkillExecutionReceipt
}

public struct DefaultContextAssembler: ContextAssembling {
    private let skillBoundary: (any SkillExecutionBoundary)?
    public init(skillBoundary: (any SkillExecutionBoundary)? = nil) { self.skillBoundary = skillBoundary }
    public func assembleContext(
        perception: Perception,
        observations: [Observation] = [],
        evaluation: Evaluation? = nil
    ) async throws -> ContextBundle {
        ContextBundle(perception: perception, memoryIDs: [], skillIDs: try await skillBoundary?.discoverSkillIDs() ?? [])
    }
}

public struct LLMReasoner: StreamingReasoning {
    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    public func reason(context: ContextBundle) async throws -> ReasoningResult {
        let systemPrompt = """
        You are the reasoning component of a personal agent.
        Answer the user's task directly and accurately.
        Provide enough detail to fully address the request; use clear steps, examples, or structure when useful.
        Keep simple answers concise.
        Do not repeat the user's task, prompt labels, or instructions.
        Do not claim an action was executed unless execution evidence is present.
        """

        let response = try await provider.complete(
            LLMRequest(
                model: provider.identity.models.first?.id ?? ModelID(rawValue: "local"),
                messages: [
                    ProviderMessage(role: .system, content: systemPrompt),
                    ProviderMessage(role: .user, content: context.perception.rawInput),
                ],
                parameters: GenerationParameters(maxOutputTokens: 768)
            )
        )

        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw KernelError.invalidStateUpdate("LLM reasoning returned empty output")
        }

        return ReasoningResult(
            summary: text,
            providerID: provider.identity.id,
            modelID: response.model
        )
    }

    public func reason(
        context: ContextBundle,
        onGenerationStarted: @Sendable () -> Void,
        onDelta: @Sendable (String) -> Void
    ) async throws -> ReasoningResult {
        let request = LLMRequest(
            model: provider.identity.models.first?.id ?? ModelID(rawValue: "local"),
            messages: [
                ProviderMessage(role: .system, content: """
                You are the reasoning component of a personal agent.
                Answer the user's task directly and accurately.
                Provide enough detail to fully address the request; use clear steps, examples, or structure when useful.
                Keep simple answers concise.
                Do not repeat the user's task, prompt labels, or instructions.
                Do not claim an action was executed unless execution evidence is present.
                """),
                ProviderMessage(role: .user, content: context.perception.rawInput),
            ],
            parameters: GenerationParameters(maxOutputTokens: 768)
        )
        var generated = ""
        var resolvedModel: ModelID?
        onGenerationStarted()
        for try await event in provider.stream(request) {
            try Task.checkCancellation()
            switch event {
            case .delta(let delta):
                guard !delta.isEmpty else { continue }
                generated += delta
                onDelta(delta)
            case .toolCall:
                // Tool calls are disabled for reasoning requests; execution belongs to Runtime.
                continue
            case .completed(let response):
                resolvedModel = response.model
                if !generated.isEmpty,
                   !response.text.isEmpty,
                   response.text != generated {
                    throw KernelError.invalidStateUpdate(
                        "LLM reasoning stream completion does not match emitted deltas"
                    )
                }
                if generated.isEmpty, !response.text.isEmpty {
                    generated = response.text
                    onDelta(response.text)
                }
            }
        }
        let text = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw KernelError.invalidStateUpdate("LLM reasoning stream returned empty output")
        }
        return ReasoningResult(
            summary: text,
            providerID: provider.identity.id,
            modelID: resolvedModel ?? provider.identity.models.first?.id
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
    private let skillBoundary: (any SkillExecutionBoundary)?
    public init(skillBoundary: (any SkillExecutionBoundary)? = nil) { self.skillBoundary = skillBoundary }
    public func plan(goalID: GoalID, context: ContextBundle, reasoning: ReasoningResult) async throws -> Plan {
        let selectedSkill: SkillID?
        if let skillBoundary {
            selectedSkill = try await skillBoundary.selectSkill(
                goalStatement: context.perception.rawInput,
                availableSkillIDs: context.skillIDs
            )
        } else {
            selectedSkill = nil
        }
        let step = PlanStep(index: 0, description: context.perception.rawInput, skillID: selectedSkill)
        return Plan(goalID: goalID, steps: [step])
    }
}

public struct DefaultProposer: Executing {
    private let skillBoundary: (any SkillExecutionBoundary)?
    public init(skillBoundary: (any SkillExecutionBoundary)? = nil) { self.skillBoundary = skillBoundary }
    public func propose(plan: Plan) async throws -> [ActionProposal] {
        var proposals: [ActionProposal] = []
        for step in plan.steps {
            let capabilities: CapabilityLevel
            if let skillID = step.skillID, let skillBoundary {
                capabilities = try await skillBoundary.requiredCapabilities(for: skillID)
            } else {
                capabilities = .read
            }
            proposals.append(ActionProposal(
                planID: plan.id,
                skillID: step.skillID,
                description: step.description,
                capabilities: capabilities
            ))
        }
        return proposals
    }
}

public struct DefaultVerifier: Verifying {
    public init() {}
    public func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult {
        guard !plan.steps.isEmpty else {
            return VerificationResult(accepted: false, notes: "Rejected empty plan")
        }
        guard !proposals.isEmpty else {
            return VerificationResult(accepted: false, notes: "Rejected plan without proposals")
        }
        guard proposals.allSatisfy({ $0.planID == plan.id }) else {
            return VerificationResult(accepted: false, notes: "Rejected proposal referencing a different plan")
        }
        guard Set(proposals.map(\.actionID)).count == proposals.count else {
            return VerificationResult(accepted: false, notes: "Rejected duplicate action identifiers")
        }
        guard proposals.allSatisfy({ !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return VerificationResult(accepted: false, notes: "Rejected empty action description")
        }
        return VerificationResult(accepted: true, notes: "Plan and action proposals passed structural verification")
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
    private let skillBoundary: (any SkillExecutionBoundary)?
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
        skillBoundary: (any SkillExecutionBoundary)? = nil,
        moduleRuntime: ModuleRuntime? = nil,
        evaluator: (any Evaluating)? = nil,
        reflector: (any Reflecting)? = nil,
        maxCycles: Int = 3
    ) {
        self.runtime = runtime
        self.eventLog = eventLog
        self.logger = logger
        self.contextAssembler = contextAssembler ?? DefaultContextAssembler(skillBoundary: skillBoundary)
        self.reasoner = reasoner ?? DefaultReasoner()
        self.planner = planner ?? DefaultPlanner(skillBoundary: skillBoundary)
        self.proposer = proposer ?? DefaultProposer(skillBoundary: skillBoundary)
        self.verifier = verifier ?? DefaultVerifier()
        self.policy = policy ?? DefaultPolicyEvaluator()
        self.approvalGate = approvalGate
        self.skillBoundary = skillBoundary
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
            try Task.checkCancellation()
            try await waitUntilRunnable()
            try Task.checkCancellation()
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
            try Task.checkCancellation()
            try await emit(
                traceID: traceID,
                kind: .contextBuilt,
                payload: ["goalID": goalID.rawValue, "memoryIDsCount": "\(context.memoryIDs.count)"]
            )

            // 3. Reasoning
            progress?(.reasoning)
            let reasoningResult = try await reasoner.reason(context: context)
            try Task.checkCancellation()

            progress?(.reasoningCompleted(reasoningResult.summary))

            // 4. Planning
            progress?(.planning)
            let plan = try await planner.plan(goalID: goalID, context: context, reasoning: reasoningResult)
            try Task.checkCancellation()
            try await emit(
                traceID: traceID,
                kind: .planProduced,
                payload: ["goalID": goalID.rawValue, "planID": plan.id.rawValue, "stepCount": "\(plan.steps.count)"]
            )

            // 5. ActionProposals
            let proposals = try await proposer.propose(plan: plan)
            try Task.checkCancellation()
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
                if let skillID = proposal.skillID {
                    payload["skillID"] = skillID.rawValue
                }
                try await emit(traceID: traceID, kind: .actionProposed, payload: payload)
            }

            // 6. Verification
            progress?(.verification)
            let verification = try await verifier.verify(plan: plan, proposals: proposals)
            try Task.checkCancellation()
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
                for (proposal, observation) in zip(proposals, obs) {
                    var payload: [String: String] = [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "summary": observation.summary,
                        "succeeded": "false",
                        "verified": "false",
                    ]
                    if let toolID = proposal.toolID {
                        payload["toolID"] = toolID.rawValue
                    }
                    if let skillID = proposal.skillID {
                        payload["skillID"] = skillID.rawValue
                    }
                    try await emit(traceID: traceID, kind: .observationProduced, payload: payload)
                }
                let eval = Evaluation(goalID: goalID, disposition: .abort, reason: "Verification rejected")
                try await emit(
                    traceID: traceID,
                    kind: .evaluationCompleted,
                    payload: [
                        "goalID": goalID.rawValue,
                        "disposition": eval.disposition.rawValue,
                        "reason": eval.reason,
                    ]
                )
                let refl = try await reflector.reflect(goalID: goalID, observations: obs, evaluation: eval)
                try await emit(
                    traceID: traceID,
                    kind: .reflectionCompleted,
                    payload: [
                        "goalID": goalID.rawValue,
                        "notes": refl.notes,
                        "shouldAdapt": "\(refl.shouldAdapt)",
                    ]
                )

                let stateUpdate = StateUpdate(
                    goalID: goalID,
                    targetStatus: .aborted,
                    evidence: [
                        "disposition": eval.disposition.rawValue,
                        "reason": eval.reason,
                        "reflection": refl.notes,
                        "observationIDs": obs.map(\.actionID.rawValue).joined(separator: ","),
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
                var denialReason = decision.reason

                if decision.requiresApproval {
                    if let gate = approvalGate {
                        try await emit(
                            traceID: traceID,
                            kind: .approvalRequested,
                            payload: ["goalID": goalID.rawValue, "actionID": proposal.actionID.rawValue]
                        )
                        allowed = try await gate.requestApproval(for: intent)
                        if !allowed {
                            denialReason = "Approval not granted"
                        }
                        try await emit(
                            traceID: traceID,
                            kind: .approvalResolved,
                            payload: ["goalID": goalID.rawValue, "actionID": proposal.actionID.rawValue, "approved": "\(allowed)"]
                        )
                    } else {
                        // Approval is a separate requirement, not an implicit grant.
                        // A permissive allowed bit must never bypass a missing gate.
                        allowed = false
                        denialReason = "Approval required but no approval gate is configured"
                    }
                }

                if !allowed {
                    var payload: [String: String] = [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "reason": denialReason,
                    ]
                    if let toolID = intent.toolID {
                        payload["toolID"] = toolID.rawValue
                    }
                    if let skillID = proposal.skillID {
                        payload["skillID"] = skillID.rawValue
                    }
                    try await emit(traceID: traceID, kind: .actionDenied, payload: payload)
                    let summary = "Denied: \(denialReason)"
                    observations.append(Observation(actionID: proposal.actionID, summary: summary, succeeded: false))
                    var observationPayload: [String: String] = [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "summary": summary,
                        "succeeded": "false",
                        "verified": "false",
                    ]
                    if let toolID = proposal.toolID {
                        observationPayload["toolID"] = toolID.rawValue
                    }
                    if let skillID = proposal.skillID {
                        observationPayload["skillID"] = skillID.rawValue
                    }
                    try await emit(traceID: traceID, kind: .observationProduced, payload: observationPayload)
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
                if let skillID = proposal.skillID {
                    authPayload["skillID"] = skillID.rawValue
                }
                try await emit(traceID: traceID, kind: .actionAuthorized, payload: authPayload)

                // Execute action
                progress?(.executing)
                let obs = try await executeProposal(proposal, traceID: traceID, goalID: goalID)
                try Task.checkCancellation()
                observations.append(obs)
                progress?(.observation(obs.summary))
            }

            // 8. Evaluation
            var evaluation = try await evaluator.evaluate(goalID: goalID, observations: observations)
            try Task.checkCancellation()
            // Answer-only proposals have no tool target. Execution success is not the answer.
            if proposals.allSatisfy({ $0.toolID == nil && $0.skillID == nil }) {
                let answer = reasoningResult.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw KernelError.invalidStateUpdate("Answer-only reasoning returned empty output") }
                evaluation = Evaluation(goalID: evaluation.goalID, disposition: evaluation.disposition, reason: answer)
            }
            // Apply the hard budget after answer projection so no later branch can
            // overwrite the terminal reason or disguise exhaustion as a normal answer.
            if evaluation.disposition == .continue, cycleCount >= maxCycles {
                evaluation = Evaluation(
                    goalID: evaluation.goalID,
                    disposition: .abort,
                    reason: "Agent loop exhausted cycle budget (maxCycles=\(maxCycles))"
                )
            }
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

            try Task.checkCancellation()
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
            if evaluation.disposition == .complete {
                progress?(.completed(evaluation.reason))
            }
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

    private func waitUntilRunnable() async throws {
        while true {
            let lifecycle = await runtime.currentState().lifecycle
            switch lifecycle {
            case .running:
                return
            case .paused:
                try await Task.sleep(for: .milliseconds(100))
            case .stopped, .failed:
                throw KernelError.runtimeNotExecutable(lifecycle)
            case .created, .starting, .pausing, .stopping:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func executeProposal(_ proposal: ActionProposal, traceID: TraceID, goalID: GoalID) async throws -> Observation {
        // A Skill ID is not a Tool ID. Until the canonical Skill execution boundary
        // is injected, never let an unhandled Skill proposal become a synthetic success.
        if let skillID = proposal.skillID {
            if let skillBoundary {
                let receipt: SkillExecutionReceipt
                do {
                    receipt = try await skillBoundary.execute(
                        skillID: skillID,
                        input: proposal.description,
                        authorizedCapabilities: proposal.capabilities
                    )
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    if error is CancellationError || (error as? ModuleRuntimeError) == .cancelled {
                        throw error
                    }
                    let summary = "Skill execution failed: \(error)"
                    let observation = Observation(actionID: proposal.actionID, summary: summary, succeeded: false)
                    try await emit(
                        traceID: traceID,
                        kind: .actionExecuted,
                        payload: [
                            "goalID": goalID.rawValue,
                            "actionID": proposal.actionID.rawValue,
                            "skillID": skillID.rawValue,
                            "description": proposal.description,
                            "summary": summary,
                            "succeeded": "false",
                            "verified": "false",
                        ]
                    )
                    try await emit(
                        traceID: traceID,
                        kind: .observationProduced,
                        payload: [
                            "goalID": goalID.rawValue,
                            "actionID": proposal.actionID.rawValue,
                            "skillID": skillID.rawValue,
                            "verified": "false",
                            "summary": summary,
                            "succeeded": "false",
                        ]
                    )
                    return observation
                }
                let verified = receipt.skillID == skillID && receipt.verified
                let succeeded = verified
                let summary = verified
                    ? "Skill '\(skillID.rawValue)' executed and verified"
                    : "Skill '\(skillID.rawValue)' did not produce verified output"
                let observation = Observation(actionID: proposal.actionID, summary: summary, succeeded: succeeded)
                try await emit(
                    traceID: traceID,
                    kind: .actionExecuted,
                    payload: [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "skillID": skillID.rawValue,
                        "description": proposal.description,
                        "summary": summary,
                        "succeeded": "\(succeeded)",
                        "verified": "\(verified)",
                    ]
                )
                try await emit(
                    traceID: traceID,
                    kind: .observationProduced,
                    payload: [
                        "goalID": goalID.rawValue,
                        "actionID": proposal.actionID.rawValue,
                        "skillID": skillID.rawValue,
                        "verified": "\(verified)",
                        "summary": summary,
                        "succeeded": "\(succeeded)",
                    ]
                )
                return observation
            }
            let observation = Observation(
                actionID: proposal.actionID,
                summary: "Skill execution unavailable: no SkillExecutionBoundary configured for '\(skillID.rawValue)'",
                succeeded: false
            )
            try await emit(
                traceID: traceID,
                kind: .observationProduced,
                payload: [
                    "goalID": goalID.rawValue,
                    "actionID": proposal.actionID.rawValue,
                    "skillID": skillID.rawValue,
                    "summary": observation.summary,
                    "succeeded": "false",
                ]
            )
            return observation
        }

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
