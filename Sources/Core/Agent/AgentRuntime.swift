import Foundation
import PAFoundation
import PAObservability
import PAEvents
import PAProviders
import PAModules
import PAMemory
import PACognition

/// M1 Kernel Runtime.
///
/// AgentRuntime is the central actor driving the agent state, goal lifecycles,
/// and subsystem coordination.
public actor AgentRuntime: AgentRuntimeCoordinating, AgentLifecycleManaging, GoalManaging {
    private let identity: AgentIdentity
    private var lifecycle: AgentLifecycle
    private var phase: AgentPhase
    private var activeGoalID: GoalID?
    private var appliedMutationTokens: Set<UUID> = []
    private let mutationEvidenceStore: any MutationEvidenceStore
    private var goalStore: [GoalID: Goal] = [:]

    private let eventLog: any EventLog
    private let logger: any AgentLogger
    private let clock: any KernelClock
    private let sessionTrace: TraceID
    public let coordination: KernelCoordinationBoundary

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal"),
        eventLog: any EventLog,
        logger: any AgentLogger = NullLoggerBridge(),
        clock: any KernelClock = SystemKernelClock(),
        coordination: KernelCoordinationBoundary = KernelCoordinationBoundary(),
        sessionTrace: TraceID = TraceID(),
        mutationEvidenceStore: (any MutationEvidenceStore)? = nil
    ) async throws {
        self.identity = identity
        self.lifecycle = .created
        self.phase = .idle
        self.eventLog = eventLog
        self.logger = logger
        self.clock = clock
        self.sessionTrace = sessionTrace
        self.coordination = coordination
        self.mutationEvidenceStore = mutationEvidenceStore ?? InMemoryMutationEvidenceStore()

        try await emit(
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
            try await emitRejection(command: GoalCommand.submit.rawValue, error: error)
            throw error
        }

        let statement = goal.statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty else {
            let error = KernelError.emptyGoalStatement
            try await emitRejection(command: GoalCommand.submit.rawValue, error: error)
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
            try await emitRejection(command: GoalCommand.submit.rawValue, error: error)
            throw error
        }
        goalStore[stored.id] = stored
        do {
            try await emit(
                kind: .goalSubmitted,
                payload: [
                    "goalID": stored.id.rawValue,
                    "status": stored.status.rawValue,
                ]
            )
        } catch {
            goalStore.removeValue(forKey: stored.id)
            throw error
        }
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
            try await emitRejection(command: GoalCommand.activate.rawValue, error: error)
            throw error
        }
        if let current = activeGoalID, current != goalID {
            let error = KernelError.activeGoalConflict(existing: current)
            try await emitRejection(command: GoalCommand.activate.rawValue, error: error)
            throw error
        }
        let previousActive = activeGoalID
        activeGoalID = goalID
        do {
            try await applyGoal(goalID, command: .activate)
        } catch {
            if activeGoalID == goalID {
                activeGoalID = previousActive
            }
            throw error
        }
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
            try await emitRejection(command: GoalCommand.resume.rawValue, error: error)
            throw error
        }
        if let current = activeGoalID, current != goalID {
            let error = KernelError.activeGoalConflict(existing: current)
            try await emitRejection(command: GoalCommand.resume.rawValue, error: error)
            throw error
        }
        let previousActive = activeGoalID
        activeGoalID = goalID
        do {
            try await applyGoal(goalID, command: .resume)
        } catch {
            if activeGoalID == goalID {
                activeGoalID = previousActive
            }
            throw error
        }
    }

    public func complete(goalID: GoalID) async throws {
        try await applyGoal(goalID, command: .complete)
        if activeGoalID == goalID {
            activeGoalID = nil
        }
    }

    /// Authoritative StateUpdate entry point.
    public func hasAppliedMutation(token: UUID) async -> Bool {
        if appliedMutationTokens.contains(token) {
            return true
        }
        return await mutationEvidenceStore.hasAppliedMutation(token: token)
    }

    public func applyStateUpdate(_ update: StateUpdate) async throws {
        guard LifecycleMachine.canExecute(in: lifecycle) else {
            let error = KernelError.runtimeNotExecutable(lifecycle)
            try await emitRejection(command: "applyStateUpdate", error: error)
            throw error
        }
        guard let goal = goalStore[update.goalID] else {
            let error = KernelError.goalNotFound(update.goalID)
            try await emitRejection(command: "applyStateUpdate", error: error)
            throw error
        }
        guard !update.evidence.isEmpty else {
            let error = KernelError.invalidStateUpdate("Missing required evidence for StateUpdate")
            try await emitRejection(command: "applyStateUpdate", error: error)
            throw error
        }

        let previousGoal = goal
        let previousActiveGoalID = activeGoalID

        do {
            let targetStatus = update.targetStatus
            if targetStatus == .completed {
                try await complete(goalID: update.goalID)
            } else if targetStatus == .aborted || targetStatus == .blocked {
                try await abort(goalID: update.goalID)
            } else if targetStatus == .active {
                if goal.status == .blocked {
                    try await resumeGoal(goalID: update.goalID)
                } else if goal.status != .active {
                    try await activate(goalID: update.goalID)
                }
            } else {
                guard let next = GoalMachine.nextStatus(goal.status, command: .suspend) else {
                    let error = KernelError.invalidGoalTransition(
                        goalID: update.goalID,
                        from: goal.status,
                        command: .suspend
                    )
                    try await emitRejection(command: "applyStateUpdate", error: error)
                    throw error
                }
                var updatedGoal = goal
                updatedGoal.status = next
                goalStore[update.goalID] = updatedGoal
            }

            var payload = update.evidence
            payload["goalID"] = update.goalID.rawValue
            payload["targetStatus"] = update.targetStatus.rawValue
            try await emit(kind: .stateUpdated, payload: payload)
            if let token = update.mutationToken {
                appliedMutationTokens.insert(token)
                try await mutationEvidenceStore.recordMutation(token: token)
            }
        } catch {
            goalStore[update.goalID] = previousGoal
            activeGoalID = previousActiveGoalID
            throw error
        }
    }

    /// Minimum coordination port: kernel requests execution, runtime owns it.
    public func invokeModule(_ invocation: ModuleInvocation) async throws -> ModuleResult {
        guard LifecycleMachine.canExecute(in: lifecycle) else {
            let error = KernelError.runtimeNotExecutable(lifecycle)
            try await emitRejection(command: "invokeModule", error: error)
            throw error
        }
        guard let modules = coordination.modules else {
            let error = KernelError.modulePortUnavailable
            try await emitRejection(command: "invokeModule", error: error)
            throw error
        }
        return try await modules.execute(invocation)
    }

    private func applyRuntime(_ command: RuntimeCommand) async throws {
        switch LifecycleMachine.apply(lifecycle, command: command) {
        case .failure(let error):
            try await emitRejection(command: command.rawValue, error: error)
            throw error
        case .success(let next):
            if LifecycleMachine.terminal.contains(next) {
                try await parkActiveGoalForTerminalLifecycle()
            }
            let previous = lifecycle
            lifecycle = next
            phase = LifecycleMachine.phase(for: next)
            try await emit(
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
    private func parkActiveGoalForTerminalLifecycle() async throws {
        guard let id = activeGoalID, var existing = goalStore[id] else {
            activeGoalID = nil
            return
        }
        if existing.status == .active {
            existing.status = .blocked
            goalStore[id] = existing
            try await emit(
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
            try await emitRejection(command: command.rawValue, error: error)
            throw error
        }
        guard let next = GoalMachine.nextStatus(existing.status, command: command) else {
            let error = KernelError.invalidGoalTransition(
                goalID: id,
                from: existing.status,
                command: command
            )
            try await emitRejection(command: command.rawValue, error: error)
            throw error
        }
        let previous = existing.status
        existing.status = next
        goalStore[id] = existing
        try await emit(
            kind: GoalMachine.eventKind(for: command),
            payload: [
                "goalID": id.rawValue,
                "from": previous.rawValue,
                "to": next.rawValue,
                "command": command.rawValue,
            ]
        )
    }

    private func emitRejection(command: String, error: KernelError) async throws {
        try await emit(
            kind: .commandRejected,
            payload: [
                "command": command,
                "error": error.description,
            ]
        )
    }

    private func emit(kind: ExecutionEventKind, payload: [String: String]) async throws {
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
            throw error
        }
    }
}

/// Isolates PAObservability from requiring PAComposition.
public struct NullLoggerBridge: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
