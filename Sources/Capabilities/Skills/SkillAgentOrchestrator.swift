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
    case skillOutsideAgentScope(SkillID)
    case agentDeclaresMissingSkill(SkillID)
}

/// Owns the Agent-level Skill loop:
/// goal -> scoped select -> execute -> independently verify.
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
        try await run(
            agent: nil,
            goalStatement: goalStatement,
            inputJSON: inputJSON,
            policy: policy
        )
    }

    public func run(
        agent: AgentManifest,
        goalStatement: String,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        try await run(
            agent: Optional(agent),
            goalStatement: goalStatement,
            inputJSON: inputJSON,
            policy: policy
        )
    }

    private func run(
        agent: AgentManifest?,
        goalStatement: String,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        if let agent {
            let available = try await runtime.discover()
            let availableIDs = Set(available.map(\.id))
            if let missing = agent.skillIDs.first(where: { !availableIDs.contains($0) }) {
                throw SkillAgentOrchestratorError.agentDeclaresMissingSkill(missing)
            }
        }

        let skillID = try await runtime.select(
            goalStatement: goalStatement,
            allowedSkillIDs: agent.map { Set($0.skillIDs) }
        )
        if let agent, !agent.skillIDs.contains(skillID) {
            throw SkillAgentOrchestratorError.skillOutsideAgentScope(skillID)
        }
        let output = try await runtime.execute(id: skillID, inputJSON: inputJSON, policy: policy)
        let verified = try await runtime.verify(id: skillID, outputJSON: output)
        guard verified else {
            throw SkillAgentOrchestratorError.verificationFailed(skillID)
        }
        return SkillAgentResult(skillID: skillID, outputJSON: output, verified: true)
    }
}
