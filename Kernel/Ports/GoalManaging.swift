import PAFoundation

public protocol GoalManaging: Sendable {
    func submit(goal: Goal) async throws
    func complete(goalID: GoalID, status: Goal.Status) async throws
}
