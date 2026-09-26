import Foundation
import PAKernel

public struct Reflection: Sendable, Codable, Equatable {
    public let notes: String
    public let shouldAdapt: Bool
    public init(notes: String, shouldAdapt: Bool) {
        self.notes = notes
        self.shouldAdapt = shouldAdapt
    }
}

public struct StateUpdate: Sendable, Codable, Equatable {
    public let goalID: GoalID
    public let targetStatus: GoalStatus
    public let evidence: [String: String]
    public let mutationToken: UUID?

    public init(
        goalID: GoalID,
        targetStatus: GoalStatus,
        evidence: [String: String] = [:],
        mutationToken: UUID? = nil
    ) {
        self.goalID = goalID
        self.targetStatus = targetStatus
        self.evidence = evidence
        self.mutationToken = mutationToken
    }
}

public protocol CognitionPipelining: Sendable {
    func run(perception: Perception) async throws -> Reflection
}
