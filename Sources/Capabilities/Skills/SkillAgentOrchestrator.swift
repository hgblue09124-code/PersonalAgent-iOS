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
    private let approvalGate: (any ApprovalGate)?

    public init(
        runtime: SkillRuntime = SkillRuntime(),
        approvalGate: (any ApprovalGate)? = nil
    ) {
        self.runtime = runtime
        self.approvalGate = approvalGate
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

    /// Execute an explicitly selected Skill through the same scoped approval boundary as Agent selection.
    public func execute(
        agent: AgentManifest,
        skillID: SkillID,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        let available = try await runtime.discover(query: "")
        let availableIDs = Set(available.map(\.id))
        if let missing = agent.skillIDs.first(where: { !availableIDs.contains($0) }) {
            throw SkillAgentOrchestratorError.agentDeclaresMissingSkill(missing)
        }
        guard agent.skillIDs.contains(skillID) else {
            throw SkillAgentOrchestratorError.skillOutsideAgentScope(skillID)
        }
        return try await executeSelected(skillID: skillID, inputJSON: inputJSON, policy: policy)
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

        // Agent execution must only intent-match Skills with a concrete executor.
        // Generic SkillRuntime.select remains manifest-only for discovery/UI callers.
        let candidateIDs: [SkillID]
        if let agent {
            candidateIDs = agent.skillIDs
        } else {
            candidateIDs = try await runtime.discover(query: "").map(\.id)
        }
        var executableSkillIDs = Set<SkillID>()
        for candidateID in candidateIDs {
            if await runtime.executorAvailability(for: candidateID) == .available {
                executableSkillIDs.insert(candidateID)
            }
        }
        let skillID = try await runtime.select(
            goalStatement: goalStatement,
            allowedSkillIDs: executableSkillIDs
        )
        if let agent, !agent.skillIDs.contains(skillID) {
            throw SkillAgentOrchestratorError.skillOutsideAgentScope(skillID)
        }
        return try await executeSelected(skillID: skillID, inputJSON: inputJSON, policy: policy)
    }

    private func executeSelected(
        skillID: SkillID,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> SkillAgentResult {
        guard await runtime.executorAvailability(for: skillID) == .available else {
            throw SkillExecutionError.unavailableSkill(skillID)
        }
        let capabilities = try await runtime.requiredCapabilities(for: skillID)
        let intent = ActionIntent(
            skillID: skillID,
            capabilities: capabilities,
            summary: "Execute skill \(skillID.rawValue)"
        )
        let decision = await policy.evaluate(intent)
        try Task.checkCancellation()

        if decision.requiresApproval {
            guard let approvalGate else {
                throw SkillExecutionError.policyRequiresApproval(decision.reason)
            }
            let approved: Bool
            do {
                approved = try await approvalGate.requestApproval(for: intent)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                throw SkillExecutionError.policyDenied("Approval gate failed: \(error)")
            }
            try Task.checkCancellation()
            guard approved else {
                throw SkillExecutionError.policyDenied("Approval not granted")
            }
        } else {
            guard decision.allowed else {
                throw SkillExecutionError.policyDenied(decision.reason)
            }
        }

        let authorizedPolicy = ApprovedSkillExecutionPolicy(skillID: skillID, capabilities: capabilities)
        let output: String
        do {
            // Execute and verify through one resolved executor instance. A second
            // registry lookup could otherwise verify with a different implementation.
            // The policy wrapper carries the exact approval decision into the Skill
            // boundary without re-prompting; ModuleRuntime still evaluates its own policy.
            output = try await runtime.executeVerified(
                id: skillID,
                inputJSON: inputJSON,
                policy: authorizedPolicy
            )
        } catch let error as SkillExecutionError {
            if case .verificationFailed(let failedID) = error {
                throw SkillAgentOrchestratorError.verificationFailed(failedID)
            }
            throw error
        }
        return SkillAgentResult(skillID: skillID, outputJSON: output, verified: true)
    }
}

private struct ApprovedSkillExecutionPolicy: PolicyEvaluating {
    let skillID: SkillID
    let capabilities: CapabilityLevel

    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        guard intent.skillID == skillID,
              capabilities.contains(intent.capabilities),
              intent.capabilities.contains(.execute) else {
            return .deny("Skill identity or capabilities mismatch after approval")
        }
        return .allow("Authorized by SkillAgentOrchestrator approval boundary")
    }
}
