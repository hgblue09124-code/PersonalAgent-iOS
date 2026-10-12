import Foundation
import PAKernel
import PARuntime
import PASkills

/// Composition owns the concrete PASkills adapter. Runtime receives only neutral contracts.
struct M6SkillExecutionAdapter: SkillExecutionBoundary, Sendable {
    private let runtime: SkillRuntime
    init(runtime: SkillRuntime) { self.runtime = runtime }

    func discoverSkillIDs() async throws -> [SkillID] {
        try await runtime.discover(query: "").map(\.id)
    }

    func selectSkill(goalStatement: String, availableSkillIDs: [SkillID]) async throws -> SkillID? {
        guard !availableSkillIDs.isEmpty else { return nil }
        do {
            return try await runtime.select(
                goalStatement: goalStatement,
                allowedSkillIDs: Set(availableSkillIDs)
            )
        } catch SkillExecutionError.noSelection {
            return nil
        }
    }

    func requiredCapabilities(for skillID: SkillID) async throws -> CapabilityLevel {
        let manifest = try await runtime.discover(query: "").first { $0.id == skillID }
        guard let manifest else { throw SkillExecutionError.unknownSkill(skillID) }
        return manifest.requiredCapabilities
    }

    func execute(
        skillID: SkillID,
        input: String,
        authorizedCapabilities: CapabilityLevel
    ) async throws -> SkillExecutionReceipt {
        // The M6 loop has already completed policy and approval. Re-check that the
        // authorization handoff matches the manifest; never grant broader capabilities here.
        let manifests = try await runtime.discover(query: "")
        guard let manifest = manifests.first(where: { $0.id == skillID }),
              manifest.requiredCapabilities == authorizedCapabilities else {
            throw SkillExecutionError.policyDenied("M6 authorization does not match Skill capabilities")
        }
        let policy = M6ApprovedSkillPolicy(capabilities: authorizedCapabilities)
        let inputJSON: String
        if let data = input.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            inputJSON = input
        } else {
            let data = try JSONSerialization.data(withJSONObject: ["text": input], options: [.sortedKeys])
            inputJSON = String(decoding: data, as: UTF8.self)
        }
        let output = try await runtime.executeVerified(id: skillID, inputJSON: inputJSON, policy: policy)
        try Task.checkCancellation()
        return SkillExecutionReceipt(skillID: skillID, output: output, verified: true)
    }
}

private struct M6ApprovedSkillPolicy: PolicyEvaluating {
    let capabilities: CapabilityLevel
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        guard intent.capabilities == capabilities else {
            return .deny("Skill capability mismatch after M6 authorization")
        }
        return .allow("Authorized by canonical M6 policy and approval gate")
    }
}
