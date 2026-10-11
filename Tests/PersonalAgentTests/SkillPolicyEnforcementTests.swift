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
