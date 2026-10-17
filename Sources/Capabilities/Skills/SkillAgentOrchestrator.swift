import Foundation
import PAKernel

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
    case agentScopeRequired
}

/// Owns the Agent-level Skill loop:
/// goal -> scoped select -> execute -> independently verify.
public actor SkillAgentOrchestrator {
    private let runtime: SkillRuntime

    public init(runtime: SkillRuntime = SkillRuntime()) {
        self.runtime = runtime
    }

    /// An Agent loop must have an explicit scope; never select from every installed Skill implicitly.
    public func run(
        goalStatement: String,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        throw SkillAgentOrchestratorError.agentScopeRequired
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
            let available = try await runtime.discover(query: "")
            let availableIDs = Set(available.map(\.id))
            // An Agent manifest is a contract: every declared Skill must exist.
            // Reject partial and fully stale scopes before intent selection.
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
        let output: String
        do {
            // Execute and verify through one resolved executor instance. A second
            // registry lookup could otherwise verify with a different implementation.
            output = try await runtime.executeVerified(id: skillID, inputJSON: inputJSON, policy: policy)
        } catch let error as SkillExecutionError {
            if case .verificationFailed(let failedID) = error {
                throw SkillAgentOrchestratorError.verificationFailed(failedID)
            }
            throw error
        }
        return SkillAgentResult(skillID: skillID, outputJSON: output, verified: true)
    }
}
