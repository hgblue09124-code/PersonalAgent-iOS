import Foundation
import PAKernel
import PARuntime
import PASkills

struct M6SkillExecutionAdapter: SkillExecutionBoundary, Sendable {
    private let runtime: SkillRuntime
    private let allowedSkillIDs: Set<SkillID>
    init(runtime: SkillRuntime, allowedSkillIDs: Set<SkillID>) {
        self.runtime = runtime
        self.allowedSkillIDs = allowedSkillIDs
    }

    func discoverSkillIDs() async throws -> [SkillID] {
        try await runtime.discover(query: "").map(\.id).filter { allowedSkillIDs.contains($0) }
    }
    func selectSkill(goalStatement: String, availableSkillIDs: [SkillID]) async throws -> SkillID? {
        let scopedIDs = availableSkillIDs.filter { allowedSkillIDs.contains($0) }
        guard !scopedIDs.isEmpty else { return nil }
        do {
            return try await runtime.select(goalStatement: goalStatement, allowedSkillIDs: Set(scopedIDs))
        } catch SkillExecutionError.noSelection { return nil }
    }
    func requiredCapabilities(for skillID: SkillID) async throws -> CapabilityLevel {
        guard allowedSkillIDs.contains(skillID),
              let manifest = try await runtime.discover(query: "").first(where: { $0.id == skillID }) else {
            throw SkillExecutionError.unknownSkill(skillID)
        }
        return manifest.requiredCapabilities
    }
    func execute(skillID: SkillID, input: String, authorizedCapabilities: CapabilityLevel) async throws -> SkillExecutionReceipt {
        guard allowedSkillIDs.contains(skillID),
              let manifest = try await runtime.discover(query: "").first(where: { $0.id == skillID }),
              manifest.requiredCapabilities == authorizedCapabilities else {
            throw SkillExecutionError.policyDenied("M6 authorization does not match Skill capabilities")
        }
        let inputJSON: String
        if let data = input.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            inputJSON = input
        } else {
            let data = try JSONSerialization.data(withJSONObject: ["text": input], options: [.sortedKeys])
            inputJSON = String(decoding: data, as: UTF8.self)
        }
        let output = try await runtime.executeVerified(
            id: skillID, inputJSON: inputJSON,
            policy: M6ApprovedSkillPolicy(capabilities: authorizedCapabilities)
        )
        try Task.checkCancellation()
        return SkillExecutionReceipt(skillID: skillID, output: output, verified: true)
    }
}
private struct M6ApprovedSkillPolicy: PolicyEvaluating {
    let capabilities: CapabilityLevel
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        intent.capabilities == capabilities
            ? .allow("Authorized by canonical M6 policy and approval gate")
            : .deny("Skill capability mismatch after M6 authorization")
    }
}
