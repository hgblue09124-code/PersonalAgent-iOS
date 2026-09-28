import Foundation
import Testing
import PAKernel
import PAEvents
import PAProviders
import PARuntime
import PAComposition

@Suite("Beta Reality Audit")
struct BetaRealityAuditTests {
    @Test("Ask vertical slice returns the real provider response")
    func askReturnsProviderResponse() async throws {
        let expected = "REAL_AGENT_RESPONSE"
        let provider = DeterministicFakeProvider(
            script: .success(
                LLMResponse(
                    text: expected,
                    finishReason: "stop",
                    model: ModelID(rawValue: "fake-text")
                )
            )
        )
        let eventLog = InMemoryEventLog()
        let runtime = try await AgentRuntime(eventLog: eventLog)
        let orchestrator = M6Orchestrator(
            runtime: runtime,
            eventLog: eventLog,
            reasoner: LLMReasoner(provider: provider)
        )

        let goal = Goal(statement: "Answer this question")
        try await runtime.submit(goal: goal)

        let evaluation = try await orchestrator.run(goalID: goal.id)

        #expect(evaluation.disposition == .complete)
        #expect(evaluation.reason == expected)
        #expect((await runtime.goal(id: goal.id))?.status == .completed)
    }

    @Test("Ask fails closed when the provider returns an empty response")
    func askFailsClosedOnEmptyProviderResponse() async throws {
        let provider = DeterministicFakeProvider(
            script: .success(
                LLMResponse(
                    text: "   ",
                    finishReason: "stop",
                    model: ModelID(rawValue: "fake-text")
                )
            )
        )
        let eventLog = InMemoryEventLog()
        let runtime = try await AgentRuntime(eventLog: eventLog)
        let orchestrator = M6Orchestrator(
            runtime: runtime,
            eventLog: eventLog,
            reasoner: LLMReasoner(provider: provider)
        )

        let goal = Goal(statement: "Answer this question")
        try await runtime.submit(goal: goal)

        await #expect(throws: KernelError.self) {
            _ = try await orchestrator.run(goalID: goal.id)
        }
    }
}
