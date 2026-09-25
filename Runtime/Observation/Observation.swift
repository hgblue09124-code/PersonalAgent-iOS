import PAKernel

public struct Observation: Sendable, Codable, Equatable {
    public let actionID: ActionID
    public let summary: String
    public let succeeded: Bool
    public init(actionID: ActionID, summary: String, succeeded: Bool) { self.actionID = actionID; self.summary = summary; self.succeeded = succeeded }
}

public struct Evaluation: Sendable, Codable, Equatable {
    public let goalID: GoalID
    public let disposition: AgencyDisposition
    public let reason: String
    public init(goalID: GoalID, disposition: AgencyDisposition, reason: String) { self.goalID = goalID; self.disposition = disposition; self.reason = reason }
}
