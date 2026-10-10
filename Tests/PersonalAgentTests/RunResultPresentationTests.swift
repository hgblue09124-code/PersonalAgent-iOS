import Testing
import PAKernel
@testable import PARuntime

@Suite("Run result presentation fail-closed behavior")
struct RunResultPresentationTests {
    private func proposal(actionID: String, toolID: String? = nil) -> ActionProposal {
        ActionProposal(
            actionID: ActionID(rawValue: actionID),
            planID: PlanID(rawValue: "plan"),
            toolID: toolID.map(ToolID.init(rawValue:)),
            description: "Perform the requested action",
            capabilities: .read
        )
    }

    private func evaluation(_ disposition: AgencyDisposition, reason: String = "Generic evaluator summary") -> Evaluation {
        Evaluation(goalID: GoalID(rawValue: "goal"), disposition: disposition, reason: reason)
    }

    @Test func answerOnlyCompletedRunReturnsReasoningArtifact() throws {
        let result = try RunResultPresentation.makeUserVisible(
            evaluation: evaluation(.complete),
            reasoningSummary: "The answer is 42.",
            proposals: [proposal(actionID: "answer")],
            observations: [Observation(actionID: ActionID(rawValue: "answer"), summary: "Executed proposal (no tool)", succeeded: true)]
        )
        #expect(result.reason == "The answer is 42.")
        #expect(result.disposition == .complete)
    }

    @Test func abortedAnswerOnlyRunDoesNotPresentReasoningAsSuccess() throws {
        let result = try RunResultPresentation.makeUserVisible(
            evaluation: evaluation(.abort, reason: "Execution denied by policy"),
            reasoningSummary: "Here is the answer.",
            proposals: [proposal(actionID: "answer")],
            observations: [Observation(actionID: ActionID(rawValue: "answer"), summary: "Denied by policy", succeeded: false)]
        )
        #expect(result.reason == "Execution denied by policy")
        #expect(result.disposition == .abort)
    }

    @Test func completedToolRunReturnsVerifiedToolOutput() throws {
        let result = try RunResultPresentation.makeUserVisible(
            evaluation: evaluation(.complete),
            reasoningSummary: "I have read the file.",
            proposals: [proposal(actionID: "read-file", toolID: "workspace.read")],
            observations: [Observation(actionID: ActionID(rawValue: "read-file"), summary: "File contents: verified-value", succeeded: true)]
        )
        #expect(result.reason == "File contents: verified-value")
        #expect(result.disposition == .complete)
    }

    @Test func failedToolRunReturnsFailureEvidenceNotToolOutput() throws {
        let result = try RunResultPresentation.makeUserVisible(
            evaluation: evaluation(.abort, reason: "Execution failed"),
            reasoningSummary: "The task succeeded.",
            proposals: [proposal(actionID: "read-file", toolID: "workspace.read")],
            observations: [Observation(actionID: ActionID(rawValue: "read-file"), summary: "Execution unverified", succeeded: false)]
        )
        #expect(result.reason == "Execution unverified")
        #expect(result.disposition == .abort)
    }

    @Test func completedToolRunWithoutObservationFailsClosed() {
        #expect(throws: KernelError.self) {
            try RunResultPresentation.makeUserVisible(
                evaluation: evaluation(.complete),
                reasoningSummary: "Pretend success",
                proposals: [proposal(actionID: "read-file", toolID: "workspace.read")],
                observations: []
            )
        }
    }
}
