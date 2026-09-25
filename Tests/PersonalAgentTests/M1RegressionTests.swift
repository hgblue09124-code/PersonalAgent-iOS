import Testing
import Foundation
import PAFoundation
import PAEvents
import PAKernel
import PARuntime

@Suite("M1 regression guards")
struct M1RegressionTests {
    @Test func stateUpdateBlockedUsesSuspendNotAbort() async throws {
        let runtime = try await makeRuntime()
        try await runtime.start()

        let goal = Goal(id: GoalID(rawValue: "state.blocked"), statement: "Block me")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)

        let update = StateUpdate(
            goalID: goal.id,
            targetStatus: .blocked,
            evidence: ["source": "regression"]
        )
        try await runtime.applyStateUpdate(update)

        #expect(await runtime.goal(id: goal.id)?.status == .blocked)
        #expect(await runtime.currentState().activeGoalID == nil)
        #expect(await runtime.invariantsHold())
    }

    @Test func terminalLifecycleDoesNotCommitGoalWhenEventAppendFails() async throws {
        let log = FailingEventLog()
        let runtime = try await AgentRuntime(
            identity: AgentIdentity(id: AgentID(rawValue: "terminal.rollback"), displayName: "TerminalRollback"),
            eventLog: log
        )

        let goal = Goal(id: GoalID(rawValue: "terminal.goal"), statement: "Stay active") 
        try await runtime.submit(goal: goal)
        try await runtime.start()
        try await runtime.activate(goalID: goal.id)

        await log.failNextAppend()
        await #expect(throws: TestEventLogError.appendFailed) {
            try await runtime.stop()
        }

        #expect(await runtime.goal(id: goal.id)?.status == .active)
        #expect(await runtime.currentState().activeGoalID == goal.id)
        #expect(await runtime.currentState().lifecycle == .running)
        #expect(await runtime.invariantsHold())

        let kinds = await log.kinds()
        #expect(!kinds.contains(.goalBlocked))
        #expect(!kinds.contains(.stopped))
    }

    @Test func goalTransitionDoesNotCommitWhenEventAppendFails() async throws {
        let log = FailingEventLog()
        let runtime = try await AgentRuntime(
            identity: AgentIdentity(id: AgentID(rawValue: "event.rollback"), displayName: "Rollback"),
            eventLog: log
        )

        let goal = Goal(id: GoalID(rawValue: "event.goal"), statement: "Keep proposed")
        try await runtime.submit(goal: goal)
        try await runtime.start()

        await log.failNextAppend()
        await #expect(throws: TestEventLogError.appendFailed) {
            try await runtime.activate(goalID: goal.id)
        }

        #expect(await runtime.goal(id: goal.id)?.status == .proposed)
        #expect(await runtime.currentState().activeGoalID == nil)
        #expect(await runtime.invariantsHold())

        let kinds = await log.kinds()
        #expect(!kinds.contains(.goalActivated))
    }
}

private enum TestEventLogError: Error, Sendable, Equatable {
    case appendFailed
}

private actor FailingEventLog: EventLog {
    private var stored: [ExecutionEvent] = []
    private var shouldFailNextAppend = false

    func append(_ event: ExecutionEvent) async throws {
        if shouldFailNextAppend {
            shouldFailNextAppend = false
            throw TestEventLogError.appendFailed
        }
        stored.append(event)
    }

    func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        stored.filter { $0.traceID == traceID }
    }

    func allEvents() async throws -> [ExecutionEvent] {
        stored
    }

    func failNextAppend() {
        shouldFailNextAppend = true
    }

    func kinds() -> [ExecutionEventKind] {
        stored.map(\.kind)
    }
}
