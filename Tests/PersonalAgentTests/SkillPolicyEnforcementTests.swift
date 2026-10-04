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
