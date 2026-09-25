import PAKernel

public struct VerificationResult: Sendable, Equatable {
    public let accepted: Bool
    public let notes: String
    public init(accepted: Bool, notes: String) {
        self.accepted = accepted
        self.notes = notes
    }
}

public protocol Verifying: Sendable {
    func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult
}
