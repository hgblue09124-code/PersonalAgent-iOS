import Foundation
import PAFoundation
import PAEvents
import PAObservability

/// Authoritative M1 kernel. Owns identity, lifecycle, goals, and coordination ports.
/// Does not call a provider, planner, or tool.
public actor AgentRuntime: AgentRuntimeCoordinating, AgentLifecycleManaging, GoalManaging {
    public let sessionTrace: TraceID
    public let coordination: KernelCoordinationBoundary

    private let identity: AgentIdentity
    private var lifecycle: AgentLifecycle
    private var phase: AgentPhase
    private var activeGoalID: GoalID?
    private var goalStore: [GoalID: Goal]
    private let eventLog: any EventLog
    private let clock: any KernelClock
    private let logger: any AgentLogger

    public init(
        identity: AgentIdentity,
        eventLog: any EventLog,
        clock: any KernelClock = SystemKernelClock(),
        logger: any AgentLogger = NullLoggerBridge(),
        coordination: KernelCoordinationBoundary = KernelCoordinationBoundary(),
        sessionTrace: TraceID = TraceID()
    ) async {
        self.identity = identity
        self.lifecycle = .created
        self.phase = .idle
        self.activeGoalID = nil
        self.goalStore = [:]
        self.eventLog = eventLog
        self.clock = clock
        self.logger = logger
        self.coordination = coordination
        self.sessionTrace = sessionTrace
        await emit(
            kind: .runtimeInitialized,
            payload: [
                "agentID": identity.id.rawValue,
                "lifecycle": AgentLifecycle.created.rawValue,
            ]
        )
    }

    public func currentState() -> AgentState {
        AgentState(
            identity: identity,
            lifecycle: lifecycle,
            phase: phase,
            activeGoalID: activeGoalID
        )
    }

    /// Authoritative invariants the runtime must hold after every command.
    public func invariantsHold() -> Bool {
        if let active = activeGoalID {
            guard let goal = goalStore[active], goal.status == .active else { return false }
            if LifecycleMachine.terminal.contains(lifecycle) { return false }
        }
        if lifecycle == .stopped && phase != .completed { return false }
        if lifecycle == .failed && phase != .failed { return false }
        if !LifecycleMachine.stable.contains(lifecycle) { return false }
        return true
    }

    public func start() async throws {
        try await applyRuntime(.start)
    }

    public func pause() async throws {
        try await applyRuntime(.pause)
    }

    public func resume() async throws {
        try await applyRuntime(.resume)
    }

    public func stop() async throws {
        try await applyRuntime(.stop)
    }

    public func submit(goal: Goal) async throws {
        if LifecycleMachine.terminal.contains(lifecycle) {
            let error = KernelError.runtimeNotExecutable(lifecycle)
            await emitRejection(command: GoalCommand.submit.rawValue, error: error)
            throw error
        }

        let statement = goal.statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty else {
            let error = KernelError.emptyGoalStatement
            await emitRejection(command: GoalCommand.submit.rawValue, error: error)
            throw error
        }

        var stored = goal
        stored.status = .proposed
        if goalStore[stored.id] != nil {
            let error = KernelError.invalidGoalTransition(
                goalID: stored.id,
                from: goalStore[stored.id]!.status,
                command: .submit
            )
            await emitRejection(command: GoalCommand.submit.rawValue, error: error)
            throw error
        }
        goalStore[stored.id] = stored
        await emit(
            kind: .goalSubmitted,
            payload: [
                "goalID": stored.id.rawValue,
                "status": stored.status.rawValue,
            ]
        )
    }

    public func abort(goalID: GoalID) async throws {
        try await applyGoal(goalID, command: .abort)
        if activeGoalID == goalID {
            activeGoalID = nil
        }
    }

    public func goals() -> [Goal] {
        goalStore.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func goal(id: GoalID) -> Goal? {
        goalStore[id]
    }

    public func activate(goalID: GoalID) async throws {
        guard LifecycleMachine.canExecute(in: lifecycle) else {
            let error = KernelError.runtimeNotExecutable(lifecycle)
            await emitRejection(command: GoalCommand.activate.rawValue, error: error)
            throw error
        }
        if let current = activeGoalID, current != goalID {
            let error = KernelError.activeGoalConflict(existing: current)
            await emitRejection(command: GoalCommand.activate.rawValue, error: error)
            throw error
        }
        try await applyGoal(goalID, command: .activate)
        activeGoalID = goalID
    }

    public func suspend(goalID: GoalID) async throws {
        try await applyGoal(goalID, command: .suspend)
        if activeGoalID == goalID {
            activeGoalID = nil
        }
    }

    public func resumeGoal(goalID: GoalID) async throws {
        guard LifecycleMachine.canExecute(in: lifecycle) else {
            let error = KernelError.runtimeNotExecutable(lifecycle)
            await emitRejection(command: GoalCommand.resume.rawValue, error: error)
            throw error
        }
        if let current = activeGoalID, current != goalID {
            let error = KernelError.activeGoalConflict(existing: current)
            await emitRejection(command: GoalCommand.resume.rawValue, error: error)
            throw error
        }
        try await applyGoal(goalID, command: .resume)
        activeGoalID = goalID
    }

    public func complete(goalID: GoalID) async throws {
        try await applyGoal(goalID, command: .complete)
        if activeGoalID == goalID {
            activeGoalID = nil
        }
    }

    private func applyRuntime(_ command: RuntimeCommand) async throws {
        switch LifecycleMachine.apply(lifecycle, command: command) {
        case .failure(let error):
            await emitRejection(command: command.rawValue, error: error)
            throw error
        case .success(let next):
            if LifecycleMachine.terminal.contains(next) {
                await parkActiveGoalForTerminalLifecycle()
            }
            let previous = lifecycle
            lifecycle = next
            phase = LifecycleMachine.phase(for: next)
            await emit(
                kind: LifecycleMachine.eventKind(for: command),
                payload: [
                    "from": previous.rawValue,
                    "to": next.rawValue,
                    "command": command.rawValue,
                ]
            )
        }
    }

    /// Stop is terminal. An active goal cannot remain executable.
    /// Pause keeps the pointer: execution is frozen, the goal is still current.
    private func parkActiveGoalForTerminalLifecycle() async {
        guard let id = activeGoalID, var existing = goalStore[id] else {
            activeGoalID = nil
            return
        }
        if existing.status == .active {
            existing.status = .blocked
            goalStore[id] = existing
            await emit(
                kind: .goalBlocked,
                payload: [
                    "goalID": id.rawValue,
                    "from": GoalStatus.active.rawValue,
                    "to": GoalStatus.blocked.rawValue,
                    "command": GoalCommand.suspend.rawValue,
                    "reason": "runtimeTerminal",
                ]
            )
        }
        activeGoalID = nil
    }

    private func applyGoal(_ id: GoalID, command: GoalCommand) async throws {
        guard var existing = goalStore[id] else {
            let error = KernelError.goalNotFound(id)
            await emitRejection(command: command.rawValue, error: error)
            throw error
        }
        guard let next = GoalMachine.nextStatus(existing.status, command: command) else {
            let error = KernelError.invalidGoalTransition(
                goalID: id,
                from: existing.status,
                command: command
            )
            await emitRejection(command: command.rawValue, error: error)
            throw error
        }
        let previous = existing.status
        existing.status = next
        goalStore[id] = existing
        await emit(
            kind: GoalMachine.eventKind(for: command),
            payload: [
                "goalID": id.rawValue,
                "from": previous.rawValue,
                "to": next.rawValue,
                "command": command.rawValue,
            ]
        )
    }

    private func emitRejection(command: String, error: KernelError) async {
        await emit(
            kind: .commandRejected,
            payload: [
                "command": command,
                "error": error.description,
            ]
        )
    }

    private func emit(kind: ExecutionEventKind, payload: [String: String]) async {
        let timestamp = await clock.now()
        let event = ExecutionEvent(
            traceID: sessionTrace,
            kind: kind,
            timestamp: timestamp,
            payload: payload
        )
        logger.log(
            LogEvent(
                level: kind == .commandRejected ? .warning : .info,
                category: "kernel",
                message: kind.rawValue,
                metadata: payload
            )
        )
        do {
            try await eventLog.append(event)
        } catch {
            logger.log(
                LogEvent(
                    level: .error,
                    category: "kernel",
                    message: "eventAppendFailed",
                    metadata: ["kind": kind.rawValue]
                )
            )
        }
    }
}

/// Isolates PAObservability from requiring PAComposition.
public struct NullLoggerBridge: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
