import Testing
import PAFoundation
import PAEvents
import PAKernel

@Suite("M1 events and determinism")
struct M1EventDeterminismTests {
    @Test func startEmitsInitializedThenStarted() async throws {
        let log = InMemoryEventLog()
        let runtime = await AgentRuntime(
            identity: AgentIdentity(id: AgentID(rawValue: "e1"), displayName: "E"),
            eventLog: log,
            sessionTrace: TraceID(rawValue: "trace.1")
        )
        try await runtime.start()
        let kinds = try await log.events(for: TraceID(rawValue: "trace.1")).map(\.kind)
        #expect(kinds == [.runtimeInitialized, .runtimeStarted])
    }

    @Test func rejectedCommandEmitsWithoutMutatingLifecycle() async throws {
        let log = InMemoryEventLog()
        let runtime = await AgentRuntime(
            identity: AgentIdentity(displayName: "E"),
            eventLog: log
        )
        await #expect(throws: KernelError.self) { try await runtime.pause() }
        #expect(await runtime.currentState().lifecycle == .created)
        let kinds = await log.kinds()
        #expect(kinds.contains(.commandRejected))
        #expect(!kinds.contains(.runtimePaused))
    }

    @Test func identicalSequencesProduceIdenticalKindStreams() async throws {
        let first = try await playStandardSequence()
        let second = try await playStandardSequence()
        #expect(first == second)
        #expect(first == [
            .runtimeInitialized,
            .runtimeStarted,
            .goalSubmitted,
            .goalActivated,
            .goalBlocked,
            .goalActivated,
            .goalCompleted,
            .runtimeStopped,
        ])
    }

    @Test func rejectionPayloadIsStructured() async throws {
        let log = InMemoryEventLog()
        let runtime = await AgentRuntime(
            identity: AgentIdentity(displayName: "E"),
            eventLog: log
        )
        await #expect(throws: KernelError.self) { try await runtime.pause() }
        let rejected = await log.allEvents().last
        #expect(rejected?.kind == .commandRejected)
        #expect(rejected?.payload["command"] == "pause")
        #expect(rejected?.payload["error"] == "invalidLifecycleTransition:created:pause")
    }

    @Test func coordinationPortsRemainUninvoked() async throws {
        let ports = KernelCoordinationBoundary()
        #expect(ports.isWiredForCognition == false)
        let runtime = await AgentRuntime(
            identity: AgentIdentity(displayName: "E"),
            eventLog: InMemoryEventLog(),
            coordination: ports
        )
        try await runtime.start()
        #expect(await runtime.coordination.isWiredForCognition == false)
        #expect(await runtime.currentState().phase == .idle)
    }
}

private func playStandardSequence() async throws -> [ExecutionEventKind] {
    let log = InMemoryEventLog()
    let runtime = await AgentRuntime(
        identity: AgentIdentity(id: AgentID(rawValue: "same"), displayName: "Same"),
        eventLog: log,
        sessionTrace: TraceID(rawValue: "same.trace")
    )
    try await runtime.start()
    let goal = Goal(id: GoalID(rawValue: "goal.same"), statement: "Sequence")
    try await runtime.submit(goal: goal)
    try await runtime.activate(goalID: goal.id)
    try await runtime.suspend(goalID: goal.id)
    try await runtime.resumeGoal(goalID: goal.id)
    try await runtime.complete(goalID: goal.id)
    try await runtime.stop()
    return try await log.events(for: TraceID(rawValue: "same.trace")).map(\.kind)
}
