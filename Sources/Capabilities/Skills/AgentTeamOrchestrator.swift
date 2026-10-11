import Foundation
import PAKernel

public struct AgentTeamMemberResult: Sendable, Equatable {
    public let agentID: String
    public let agentName: String
    public let skillResult: SkillAgentResult

    public init(agentID: String, agentName: String, skillResult: SkillAgentResult) {
        self.agentID = agentID
        self.agentName = agentName
        self.skillResult = skillResult
    }
}

public struct AgentTeamResult: Sendable, Equatable {
    public let members: [AgentTeamMemberResult]

    public init(members: [AgentTeamMemberResult]) {
        self.members = members
    }
}

public enum AgentTeamOrchestratorError: Error, Sendable, Equatable {
    case noAgents
    case noMatchingSkills
}

/// Executes matching Agent.md profiles in a deterministic sequence. Unmatched
/// agents are skipped; policy, scope, and output verification errors fail closed.
public actor AgentTeamOrchestrator {
    private let skillOrchestrator: SkillAgentOrchestrator

    public init(skillOrchestrator: SkillAgentOrchestrator) {
        self.skillOrchestrator = skillOrchestrator
    }

    public func run(
        agents: [AgentManifest],
        goalStatement: String,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> AgentTeamResult {
        guard !agents.isEmpty else { throw AgentTeamOrchestratorError.noAgents }

        var members: [AgentTeamMemberResult] = []
        for agent in agents.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            do {
                let result = try await skillOrchestrator.run(
                    agent: agent,
                    goalStatement: goalStatement,
                    inputJSON: inputJSON,
                    policy: policy
                )
                members.append(AgentTeamMemberResult(
                    agentID: agent.id,
                    agentName: agent.name,
                    skillResult: result
                ))
            } catch SkillExecutionError.noSelection {
                // A team may contain specialists for other goals.
                continue
            }
        }

        guard !members.isEmpty else { throw AgentTeamOrchestratorError.noMatchingSkills }
        return AgentTeamResult(members: members)
    }
}
