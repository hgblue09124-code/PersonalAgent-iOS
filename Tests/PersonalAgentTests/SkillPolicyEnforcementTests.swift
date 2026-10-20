import Foundation
import Testing
import PAKernel
import PARuntime
import PASkills

@Suite("Skill Policy Enforcement")
struct SkillPolicyEnforcementTests {
    struct DenyPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .deny("skill execution denied by test policy")
        }
    }

    struct ApprovalPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .approve("skill execution requires approval")
        }
    }


    @Test("Settings-backed policy honors explicit Alpha capabilities")
    func settingsBackedPolicyHonorsCapabilityToggles() async {
        let suiteName = "PersonalAgentPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "permissions.capability.read")
        defaults.set(true, forKey: "permissions.capability.write")
        defaults.set(true, forKey: "permissions.capability.execute")
        defaults.set(false, forKey: "permissions.capability.network")
        let policy = SettingsBackedPolicyEvaluator(defaults: defaults)

        let workspaceWrite = await policy.evaluate(
            ActionIntent(capabilities: [.read, .write, .execute], summary: "create workspace file")
        )
        #expect(workspaceWrite.allowed)

        let network = await policy.evaluate(
            ActionIntent(capabilities: [.network, .execute], summary: "network action")
        )
        #expect(!network.allowed)

        defaults.set(false, forKey: "permissions.capability.write")
        let deniedWrite = await policy.evaluate(
            ActionIntent(capabilities: [.write, .execute], summary: "create workspace file")
        )
        #expect(!deniedWrite.allowed)
    }

    @Test("Settings-backed policy requires approval for destructive actions")
    func settingsBackedPolicyRequiresDestructiveApproval() async {
        let suiteName = "PersonalAgentPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "permissions.capability.execute")
        let decision = await SettingsBackedPolicyEvaluator(defaults: defaults).evaluate(
            ActionIntent(capabilities: [.execute, .destructive], summary: "destructive action")
        )
        #expect(!decision.allowed)
        #expect(decision.requiresApproval)
    }

    @Test("default policy denies execution without an explicit grant")
    func defaultPolicyDeniesExecutionWithoutGrant() async {
        let decision = await DefaultPolicyEvaluator().evaluate(
            ActionIntent(capabilities: [.read, .execute], summary: "run Skill")
        )
        #expect(!decision.allowed)
        #expect(!decision.requiresApproval)
    }

    @Test("default policy permits read-only actions")
    func defaultPolicyPermitsReadOnlyActions() async {
        let decision = await DefaultPolicyEvaluator().evaluate(
            ActionIntent(capabilities: .read, summary: "read manifest")
        )
        #expect(decision.allowed)
    }

    @Test("denied policy fails closed")
    func deniedPolicyFailsClosed() async {
        let runtime = SkillRuntime()
        await #expect(throws: SkillRuntimeError.policyDenied("skill execution denied by test policy")) {
            try await runtime.execute(
                id: SkillRuntime.normalizationManifest.id,
                inputJSON: #"{"text":" hello "}"#,
                policy: DenyPolicy()
            )
        }
    }

    @Test("approval requirement fails closed at skill boundary")
    func approvalPolicyFailsClosed() async {
        let runtime = SkillRuntime()
        await #expect(throws: SkillRuntimeError.policyRequiresApproval("skill execution requires approval")) {
            try await runtime.execute(
                id: SkillRuntime.normalizationManifest.id,
                inputJSON: #"{"text":" hello "}"#,
                policy: ApprovalPolicy()
            )
        }
    }
}
