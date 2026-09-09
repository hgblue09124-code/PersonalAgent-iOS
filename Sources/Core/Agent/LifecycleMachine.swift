import PAFoundation
import PAEvents

/// Pure lifecycle graph derived from M0 `AgentLifecycle`.
///
/// Stable states: created, running, paused, stopped, failed.
/// Transient cases starting/pausing/stopping exist on the M0 enum for
/// observability of in-flight commands. M1 commands are atomic: a successful
/// command ends in a stable state and records the transient only as an event
/// waypoint, never as a parked state.
public enum LifecycleMachine: Sendable {
    public static let stable: Set<AgentLifecycle> = [
        .created, .running, .paused, .stopped, .failed,
    ]

    public static let terminal: Set<AgentLifecycle> = [.stopped, .failed]

    public static func canExecute(in state: AgentLifecycle) -> Bool {
        state == .running
    }

    public static func apply(
        _ state: AgentLifecycle,
        command: RuntimeCommand
    ) -> Result<AgentLifecycle, KernelError> {
        switch (state, command) {
        case (.created, .start):
            return .success(.running)
        case (.created, .stop):
            return .success(.stopped)
        case (.running, .pause):
            return .success(.paused)
        case (.running, .stop):
            return .success(.stopped)
        case (.paused, .resume):
            return .success(.running)
        case (.paused, .stop):
            return .success(.stopped)
        default:
            return .failure(.invalidLifecycleTransition(from: state, command: command))
        }
    }

    public static func eventKind(for command: RuntimeCommand) -> ExecutionEventKind {
        switch command {
        case .start: return .runtimeStarted
        case .pause: return .runtimePaused
        case .resume: return .runtimeResumed
        case .stop: return .runtimeStopped
        }
    }

    public static func phase(for lifecycle: AgentLifecycle) -> AgentPhase {
        switch lifecycle {
        case .failed: return .failed
        case .stopped: return .completed
        case .created, .starting, .running, .pausing, .paused, .stopping:
            return .idle
        }
    }
}
