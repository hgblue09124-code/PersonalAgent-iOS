import PAFoundation
import PAPolicy
import PATools
import PACognition
import PAModules

public enum AgencyStage: String, Sendable, Codable, CaseIterable {
    case goal
    case plan
    case execute
    case observe
    case evaluate
    case adapt
    case continueOrCompleteOrAbort
}

public enum AgencyDisposition: String, Sendable, Codable {
    case `continue`
    case complete
    case abort
}

public struct Observation: Sendable, Equatable {
    public let actionID: ActionID
    public let summary: String
    public let succeeded: Bool

    public init(actionID: ActionID, summary: String, succeeded: Bool) {
        self.actionID = actionID
        self.summary = summary
        self.succeeded = succeeded
    }
}

public struct Evaluation: Sendable, Equatable {
    public let goalID: GoalID
    public let disposition: AgencyDisposition
    public let reason: String

    public init(goalID: GoalID, disposition: AgencyDisposition, reason: String) {
        self.goalID = goalID
        self.disposition = disposition
        self.reason = reason
    }
}

/// Execution evidence returned from Agency -> Cognition feedback loop.
public struct CognitionFeedback: Sendable, Equatable {
    public let observations: [Observation]
    public let evaluation: Evaluation

    public init(observations: [Observation], evaluation: Evaluation) {
        self.observations = observations
        self.evaluation = evaluation
    }
}

public protocol ActionAuthorizing: Sendable {
    func authorize(proposal: ActionProposal, policy: any PolicyEvaluating, gate: (any ApprovalGate)?) async throws -> ActionIntent?
}

public struct DefaultActionAuthorizer: ActionAuthorizing {
    public init() {}

    public func authorize(proposal: ActionProposal, policy: any PolicyEvaluating, gate: (any ApprovalGate)?) async throws -> ActionIntent? {
        let intent = ActionIntent(
            actionID: proposal.actionID,
            toolID: ToolID(rawValue: proposal.description),
            capabilities: proposal.capabilities,
            summary: proposal.description
        )

        let decision = await policy.evaluate(intent)
        if decision.allowed {
            return intent
        }

        if decision.requiresApproval {
            guard let gate = gate else {
                return nil
            }
            let approved = try await gate.requestApproval(for: intent)
            if approved {
                return intent
            }
            return nil
        }

        return nil
    }
}

public protocol CognitionPipelining: Sendable {
    func process(perception: Perception, goalID: GoalID) async throws -> CognitionOutput
    func reflect(feedback: CognitionFeedback) async throws -> Reflection
    func run(perception: Perception) async throws -> Reflection
}

/// Extension for default backwards compatibility where needed
extension CognitionPipelining {
    public func run(perception: Perception) async throws -> Reflection {
        let dummyGoalID = GoalID()
        let output = try await process(perception: perception, goalID: dummyGoalID)
        let feedback = CognitionFeedback(
            observations: output.proposals.map { Observation(actionID: $0.actionID, summary: "executed", succeeded: output.verification.accepted) },
            evaluation: Evaluation(goalID: dummyGoalID, disposition: .complete, reason: output.verification.notes)
        )
        return try await reflect(feedback: feedback)
    }
}

public protocol AgencyLooping: Sendable {
    func executePlan(
        output: CognitionOutput,
        policy: any PolicyEvaluating,
        gate: (any ApprovalGate)?,
        moduleExecutor: (any ModuleExecuting)?
    ) async throws -> CognitionFeedback

    func run(goalID: GoalID) async throws -> Evaluation
}
