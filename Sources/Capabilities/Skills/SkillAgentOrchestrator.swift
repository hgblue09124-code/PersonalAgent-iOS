import Foundation
import PAKernel
import PARuntime

public struct SkillAgentResult: Sendable, Equatable {
    public let skillID: SkillID
    public let outputJSON: String
    public let verified: Bool

    public init(skillID: SkillID, outputJSON: String, verified: Bool) {
        self.skillID = skillID
        self.outputJSON = outputJSON
        self.verified = verified
    }
}

public enum SkillAgentOrchestratorError: Error, Sendable, Equatable {
    case verificationFailed(SkillID)
}

/// Owns the Agent-level Skill loop:
/// goal -> select -> execute -> independently verify.
/// The UI and chat session should call this boundary rather than reimplementing
/// Skill selection/execution semantics.
public actor SkillAgentOrchestrator {
    private let runtime: SkillRuntime

    public init(runtime: SkillRuntime = SkillRuntime()) {
        self.runtime = runtime
    }

    public func run(
        goalStatement: String,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        let skillID = try await runtime.select(goalStatement: goalStatement)
        let output = try await runtime.execute(
            id: skillID,
            inputJSON: inputJSON,
            policy: policy
        )
        let verified = try await runtime.verify(
            id: skillID,
            outputJSON: output
        )
        guard verified else {
            throw SkillAgentOrchestratorError.verificationFailed(skillID)
        }
        return SkillAgentResult(
            skillID: skillID,
            outputJSON: output,
            verified: true
        )
    }
}
