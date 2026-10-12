import Testing
import PAKernel
import PARuntime

@Test func defaultProposerPreservesPlannedSkillIdentity() async throws {
    let skillID = SkillID(rawValue: "skill.contract-test")
    let plan = Plan(
        goalID: GoalID(),
        steps: [PlanStep(index: 0, description: "execute selected skill", skillID: skillID)]
    )

    let proposals = try await DefaultProposer().propose(plan: plan)

    #expect(proposals.count == 1)
    #expect(proposals.first?.skillID == skillID)
    #expect(proposals.first?.toolID == nil)
}
