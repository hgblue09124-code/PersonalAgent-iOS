import PAFoundation

public enum RuntimeCommand: String, Sendable, Codable, Equatable {
    case start
    case pause
    case resume
    case stop
}

public enum GoalCommand: String, Sendable, Codable, Equatable {
    case submit
    case activate
    case suspend
    case resume
    case complete
    case abort
}

public enum KernelError: Error, Sendable, Equatable {
    case invalidLifecycleTransition(from: AgentLifecycle, command: RuntimeCommand)
    case invalidGoalTransition(goalID: GoalID, from: GoalStatus, command: GoalCommand)
    case goalNotFound(GoalID)
    case emptyGoalStatement
    case runtimeNotExecutable(AgentLifecycle)
    case activeGoalConflict(existing: GoalID)
    case identityMutationRejected
    case modulePortUnavailable
}

extension KernelError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidLifecycleTransition(let from, let command):
            return "invalidLifecycleTransition:\(from.rawValue):\(command.rawValue)"
        case .invalidGoalTransition(let goalID, let from, let command):
            return "invalidGoalTransition:\(goalID.rawValue):\(from.rawValue):\(command.rawValue)"
        case .goalNotFound(let id):
            return "goalNotFound:\(id.rawValue)"
        case .emptyGoalStatement:
            return "emptyGoalStatement"
        case .runtimeNotExecutable(let lifecycle):
            return "runtimeNotExecutable:\(lifecycle.rawValue)"
        case .activeGoalConflict(let existing):
            return "activeGoalConflict:\(existing.rawValue)"
        case .identityMutationRejected:
            return "identityMutationRejected"
        case .modulePortUnavailable:
            return "modulePortUnavailable"
        }
    }
}
