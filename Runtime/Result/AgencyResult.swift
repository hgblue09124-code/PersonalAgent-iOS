import PAKernel

public enum AgencyStage: String, Sendable, Codable, CaseIterable { case goal, plan, execute, observe, evaluate, adapt, continueOrCompleteOrAbort }
public enum AgencyDisposition: String, Sendable, Codable { case `continue`, complete, abort }
public protocol AgencyLooping: Sendable { func run(goalID: GoalID) async throws -> Evaluation }
