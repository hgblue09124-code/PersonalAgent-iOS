import PACognition
import PAPolicy

public protocol ActionAuthorizing: Sendable {
    func authorize(_ proposal: ActionProposal, policy: any PolicyEvaluating) async throws -> ActionIntent
}
