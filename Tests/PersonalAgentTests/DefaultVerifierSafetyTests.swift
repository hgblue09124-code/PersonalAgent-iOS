import Foundation
import Testing
import PAKernel
import PARuntime

@Suite("Default verifier fail-closed behavior")
struct DefaultVerifierSafetyTests {
    @Test func rejectsEmptyPlan() async throws {
        let goalID = GoalID(rawValue: "goal")
        let plan = Plan(goalID: goalID, steps: [])
        let result = try await DefaultVerifier().verify(plan: plan, proposals: [])
        #expect(!result.accepted)
    }

    @Test func rejectsEmptyProposals() async throws {
        let goalID = GoalID(rawValue: "goal")
        let plan = Plan(goalID: goalID, steps: [
            PlanStep(index: 0, description: "Answer the request", skillID: nil)
        ])
        let result = try await DefaultVerifier().verify(plan: plan, proposals: [])
        #expect(!result.accepted)
    }

    @Test func rejectsProposalFromDifferentPlan() async throws {
        let goalID = GoalID(rawValue: "goal")
        let plan = Plan(goalID: goalID, steps: [
            PlanStep(index: 0, description: "Answer the request", skillID: nil)
        ])
        let proposal = ActionProposal(
            planID: PlanID(rawValue: "different-plan"),
            description: "Answer the request",
            capabilities: .read
        )
        let result = try await DefaultVerifier().verify(plan: plan, proposals: [proposal])
        #expect(!result.accepted)
    }

    @Test func rejectsDuplicateActionIDs() async throws {
        let goalID = GoalID(rawValue: "goal")
        let plan = Plan(goalID: goalID, steps: [
            PlanStep(index: 0, description: "First", skillID: nil),
            PlanStep(index: 1, description: "Second", skillID: nil)
        ])
        let actionID = ActionID(rawValue: "duplicate-action")
        let proposals = [
            ActionProposal(actionID: actionID, planID: plan.id, description: "First", capabilities: .read),
            ActionProposal(actionID: actionID, planID: plan.id, description: "Second", capabilities: .read)
        ]
        let result = try await DefaultVerifier().verify(plan: plan, proposals: proposals)
        #expect(!result.accepted)
    }

    @Test func acceptsWellFormedAnswerOnlyProposal() async throws {
        let goalID = GoalID(rawValue: "goal")
        let plan = Plan(goalID: goalID, steps: [
            PlanStep(index: 0, description: "Answer the request", skillID: nil)
        ])
        let proposal = ActionProposal(
            planID: plan.id,
            description: "Answer the request",
            capabilities: .read
        )
        let result = try await DefaultVerifier().verify(plan: plan, proposals: [proposal])
        #expect(result.accepted)
    }
}
