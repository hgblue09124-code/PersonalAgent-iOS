import PAFoundation
import PAPolicy
import PATools
import PACognition

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

public protocol AgencyLooping: Sendable {
    func run(goalID: GoalID) async throws -> Evaluation
}

public protocol ActionAuthorizing: Sendable {
    func authorize(_ proposal: ActionProposal, policy: any PolicyEvaluating) async throws -> ActionIntent
}
