import Testing
import PAFoundation
import PAEvents
import PAKernel

@Suite("M1 concurrency")
struct M1ConcurrencyTests {
    @Test func concurrentCommandsLeaveAValidStableState() async throws {
        let runtime = await makeRuntime()
        try await runtime.start()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await runtime.pause() }
            group.addTask { try? await runtime.resume() }
            group.addTask { try? await runtime.pause() }
            group.addTask { try? await runtime.resume() }
        }
        let lifecycle = await runtime.currentState().lifecycle
        #expect(LifecycleMachine.stable.contains(lifecycle))
        #expect(lifecycle == .running || lifecycle == .paused)
        #expect(await runtime.invariantsHold())
    }

    @Test func concurrentSubmitDoesNotCorruptStore() async throws {
        let runtime = try await startedRuntime()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let goal = Goal(
                        id: GoalID(rawValue: "g.\(index)"),
                        statement: "Goal \(index)"
                    )
                    try? await runtime.submit(goal: goal)
                }
            }
        }
        #expect(await runtime.goals().count == 20)
        #expect(await runtime.currentState().lifecycle == .running)
    }

    @Test func actorSerializesActivateConflict() async throws {
        let runtime = try await startedRuntime()
        let first = Goal(id: GoalID(rawValue: "one"), statement: "One")
        let second = Goal(id: GoalID(rawValue: "two"), statement: "Two")
        try await runtime.submit(goal: first)
        try await runtime.submit(goal: second)
        async let a = activateResult(runtime, first.id)
        async let b = activateResult(runtime, second.id)
        let results = await [a, b]
        let successes = results.filter { $0 }.count
        #expect(successes == 1)
        let active = await runtime.currentState().activeGoalID
        #expect(active == first.id || active == second.id)
    }
}

private func activateResult(_ runtime: AgentRuntime, _ id: GoalID) async -> Bool {
    do {
        try await runtime.activate(goalID: id)
        return true
    } catch {
        return false
    }
}
