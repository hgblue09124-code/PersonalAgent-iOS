import Testing
import PAFoundation
import PAEvents
import PAKernel

@Suite("M1 goal management")
struct M1GoalTests {
    @Test func submitCreatesProposedGoalWithoutActivating() async throws {
        let runtime = await makeRuntime()
        let goal = Goal(id: GoalID(rawValue: "g1"), statement: "Remember the weekly review")
        try await runtime.submit(goal: goal)
        #expect(await runtime.currentState().activeGoalID == nil)
        #expect(await runtime.goal(id: goal.id)?.status == .proposed)
    }

    @Test func emptyStatementIsRejected() async throws {
        let runtime = await makeRuntime()
        await #expect(throws: KernelError.emptyGoalStatement) {
            try await runtime.submit(goal: Goal(statement: "   "))
        }
        #expect(await runtime.goals().isEmpty)
    }

    @Test func activateRequiresRunningRuntime() async throws {
        let runtime = await makeRuntime()
        let goal = Goal(id: GoalID(rawValue: "g2"), statement: "Draft architecture note")
        try await runtime.submit(goal: goal)
        await #expect(throws: KernelError.runtimeNotExecutable(.created)) {
            try await runtime.activate(goalID: goal.id)
        }
        try await runtime.start()
        try await runtime.activate(goalID: goal.id)
        #expect(await runtime.currentState().activeGoalID == goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .active)
    }

    @Test func secondActiveGoalIsRejected() async throws {
        let runtime = try await startedRuntime()
        let a = Goal(id: GoalID(rawValue: "a"), statement: "A")
        let b = Goal(id: GoalID(rawValue: "b"), statement: "B")
        try await runtime.submit(goal: a)
        try await runtime.submit(goal: b)
        try await runtime.activate(goalID: a.id)
        await #expect(throws: KernelError.activeGoalConflict(existing: a.id)) {
            try await runtime.activate(goalID: b.id)
        }
        #expect(await runtime.goal(id: b.id)?.status == .proposed)
    }

    @Test func suspendAndResumeGoal() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "g3"), statement: "Hold")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        try await runtime.suspend(goalID: goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .blocked)
        #expect(await runtime.currentState().activeGoalID == nil)
        try await runtime.resumeGoal(goalID: goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .active)
        #expect(await runtime.currentState().activeGoalID == goal.id)
    }

    @Test func completeAndAbortClearActivePointer() async throws {
        let runtime = try await startedRuntime()
        let one = Goal(id: GoalID(rawValue: "c1"), statement: "Finish")
        try await runtime.submit(goal: one)
        try await runtime.activate(goalID: one.id)
        try await runtime.complete(goalID: one.id)
        #expect(await runtime.goal(id: one.id)?.status == .completed)
        #expect(await runtime.currentState().activeGoalID == nil)

        let two = Goal(id: GoalID(rawValue: "c2"), statement: "Cancel")
        try await runtime.submit(goal: two)
        try await runtime.activate(goalID: two.id)
        try await runtime.abort(goalID: two.id)
        #expect(await runtime.goal(id: two.id)?.status == .aborted)
        #expect(await runtime.currentState().activeGoalID == nil)
    }

    @Test func invalidGoalTransitionLeavesStoreIntact() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "g4"), statement: "Done")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        try await runtime.complete(goalID: goal.id)
        await #expect(throws: KernelError.self) {
            try await runtime.activate(goalID: goal.id)
        }
        #expect(await runtime.goal(id: goal.id)?.status == .completed)
    }

    @Test func unknownGoalIsNotFound() async throws {
        let runtime = try await startedRuntime()
        await #expect(throws: KernelError.goalNotFound(GoalID(rawValue: "missing"))) {
            try await runtime.activate(goalID: GoalID(rawValue: "missing"))
        }
    }

    @Test func duplicateSubmitIsRejected() async throws {
        let runtime = await makeRuntime()
        let goal = Goal(id: GoalID(rawValue: "dup"), statement: "Once")
        try await runtime.submit(goal: goal)
        await #expect(throws: KernelError.self) {
            try await runtime.submit(goal: goal)
        }
        #expect(await runtime.goals().count == 1)
    }

    @Test func abortFromProposed() async throws {
        let runtime = await makeRuntime()
        let goal = Goal(id: GoalID(rawValue: "p1"), statement: "Never start")
        try await runtime.submit(goal: goal)
        try await runtime.abort(goalID: goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .aborted)
        #expect(await runtime.invariantsHold())
    }

    @Test func completeFromBlocked() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "p2"), statement: "Finish blocked")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        try await runtime.suspend(goalID: goal.id)
        try await runtime.complete(goalID: goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .completed)
        #expect(await runtime.currentState().activeGoalID == nil)
    }

    @Test func abortFromBlocked() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "p3"), statement: "Abort blocked")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        try await runtime.suspend(goalID: goal.id)
        try await runtime.abort(goalID: goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .aborted)
    }

    @Test func goalMachineRejectsIllegalPairs() {
        #expect(GoalMachine.nextStatus(.proposed, command: .complete) == nil)
        #expect(GoalMachine.nextStatus(.proposed, command: .suspend) == nil)
        #expect(GoalMachine.nextStatus(.completed, command: .activate) == nil)
        #expect(GoalMachine.nextStatus(.aborted, command: .resume) == nil)
        #expect(GoalMachine.nextStatus(.active, command: .resume) == nil)
        #expect(GoalMachine.nextStatus(.blocked, command: .activate) == nil)
        #expect(GoalMachine.nextStatus(.proposed, command: .activate) == .active)
        #expect(GoalMachine.terminal.contains(.completed))
        #expect(GoalMachine.terminal.contains(.aborted))
    }
}

func startedRuntime() async throws -> AgentRuntime {
    let runtime = await makeRuntime()
    try await runtime.start()
    return runtime
}
