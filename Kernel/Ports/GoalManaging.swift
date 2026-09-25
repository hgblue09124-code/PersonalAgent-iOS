import PAFoundation

public protocol GoalManaging: Sendable {
    func goals() async -> [Goal]
    func goal(id: GoalID) async -> Goal?
    func activate(goalID: GoalID) async throws
    func suspend(goalID: GoalID) async throws
    func resumeGoal(goalID: GoalID) async throws
    func complete(goalID: GoalID) async throws
}
