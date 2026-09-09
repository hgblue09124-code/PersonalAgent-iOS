import Testing
import PAFoundation
import PAEvents
import PAKernel

@Suite("M1 lifecycle machine")
struct M1LifecycleTests {
    @Test func validHappyPath() async throws {
        let log = InMemoryEventLog()
        let runtime = await AgentRuntime(
            identity: AgentIdentity(id: AgentID(rawValue: "agent.1"), displayName: "A"),
            eventLog: log
        )
        #expect(await runtime.currentState().lifecycle == .created)
        try await runtime.start()
        #expect(await runtime.currentState().lifecycle == .running)
        try await runtime.pause()
        #expect(await runtime.currentState().lifecycle == .paused)
        try await runtime.resume()
        #expect(await runtime.currentState().lifecycle == .running)
        try await runtime.stop()
        #expect(await runtime.currentState().lifecycle == .stopped)
        #expect(await runtime.currentState().phase == .completed)
    }

    @Test func stopFromCreatedIsTerminal() async throws {
        let runtime = await makeRuntime()
        try await runtime.stop()
        #expect(await runtime.currentState().lifecycle == .stopped)
        await #expect(throws: KernelError.self) { try await runtime.start() }
        await #expect(throws: KernelError.self) { try await runtime.resume() }
    }

    @Test func repeatedStartIsRejected() async throws {
        let runtime = await makeRuntime()
        try await runtime.start()
        await #expect(throws: KernelError.invalidLifecycleTransition(from: .running, command: .start)) {
            try await runtime.start()
        }
        #expect(await runtime.currentState().lifecycle == .running)
    }

    @Test func pauseWhenNotRunningIsRejected() async throws {
        let runtime = await makeRuntime()
        await #expect(throws: KernelError.invalidLifecycleTransition(from: .created, command: .pause)) {
            try await runtime.pause()
        }
        #expect(await runtime.currentState().lifecycle == .created)
    }

    @Test func resumeWhenNotPausedIsRejected() async throws {
        let runtime = await makeRuntime()
        try await runtime.start()
        await #expect(throws: KernelError.invalidLifecycleTransition(from: .running, command: .resume)) {
            try await runtime.resume()
        }
        #expect(await runtime.currentState().lifecycle == .running)
    }

    @Test func startFromPausedMustUseResume() async throws {
        let runtime = await makeRuntime()
        try await runtime.start()
        try await runtime.pause()
        await #expect(throws: KernelError.invalidLifecycleTransition(from: .paused, command: .start)) {
            try await runtime.start()
        }
        try await runtime.resume()
        #expect(await runtime.currentState().lifecycle == .running)
    }

    @Test func stopWhenStoppedIsRejectedAndStateHolds() async throws {
        let runtime = await makeRuntime()
        try await runtime.stop()
        await #expect(throws: KernelError.invalidLifecycleTransition(from: .stopped, command: .stop)) {
            try await runtime.stop()
        }
        #expect(await runtime.currentState().lifecycle == .stopped)
    }

    @Test func identityIsImmutableAcrossCommands() async throws {
        let identity = AgentIdentity(id: AgentID(rawValue: "fixed"), displayName: "Personal")
        let runtime = await AgentRuntime(identity: identity, eventLog: InMemoryEventLog())
        try await runtime.start()
        try await runtime.pause()
        try await runtime.resume()
        let state = await runtime.currentState()
        #expect(state.identity.id == identity.id)
        #expect(state.identity.displayName == "Personal")
    }

    @Test func machineTableMatchesRuntime() {
        #expect(LifecycleMachine.apply(.created, command: .start) == .success(.running))
        #expect(LifecycleMachine.apply(.running, command: .pause) == .success(.paused))
        #expect(LifecycleMachine.apply(.paused, command: .resume) == .success(.running))
        #expect(LifecycleMachine.apply(.running, command: .stop) == .success(.stopped))
        #expect(LifecycleMachine.apply(.failed, command: .start).isFailure)
        #expect(LifecycleMachine.canExecute(in: .running))
        #expect(!LifecycleMachine.canExecute(in: .paused))
        #expect(LifecycleMachine.terminal.contains(.stopped))
    }

    @Test func exhaustiveStableGraph() {
        let states: [AgentLifecycle] = [.created, .running, .paused, .stopped, .failed]
        let commands: [RuntimeCommand] = [.start, .pause, .resume, .stop]
        var allowed = 0
        var rejected = 0
        for state in states {
            for command in commands {
                switch LifecycleMachine.apply(state, command: command) {
                case .success(let next):
                    allowed += 1
                    #expect(LifecycleMachine.stable.contains(next))
                    #expect(!LifecycleMachine.terminal.contains(state))
                case .failure:
                    rejected += 1
                }
            }
        }
        #expect(allowed == 6)
        #expect(rejected == 14)
    }

    @Test func stopParksActiveGoal() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "park"), statement: "Park on stop")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        #expect(await runtime.invariantsHold())
        try await runtime.stop()
        #expect(await runtime.currentState().lifecycle == .stopped)
        #expect(await runtime.currentState().activeGoalID == nil)
        #expect(await runtime.goal(id: goal.id)?.status == .blocked)
        #expect(await runtime.invariantsHold())
        await #expect(throws: KernelError.runtimeNotExecutable(.stopped)) {
            try await runtime.submit(goal: Goal(statement: "Too late"))
        }
    }

    @Test func pauseKeepsActiveGoalPointer() async throws {
        let runtime = try await startedRuntime()
        let goal = Goal(id: GoalID(rawValue: "hold"), statement: "Hold across pause")
        try await runtime.submit(goal: goal)
        try await runtime.activate(goalID: goal.id)
        try await runtime.pause()
        #expect(await runtime.currentState().lifecycle == .paused)
        #expect(await runtime.currentState().activeGoalID == goal.id)
        #expect(await runtime.goal(id: goal.id)?.status == .active)
        #expect(await runtime.invariantsHold())
        await #expect(throws: KernelError.runtimeNotExecutable(.paused)) {
            try await runtime.activate(goalID: goal.id)
        }
    }
}

extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

func makeRuntime() async -> AgentRuntime {
    await AgentRuntime(
        identity: AgentIdentity(id: AgentID(rawValue: "agent.test"), displayName: "Test"),
        eventLog: InMemoryEventLog()
    )
}
