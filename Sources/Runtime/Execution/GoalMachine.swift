import PAFoundation
import PAEvents

/// Goal graph mapped onto M0 `GoalStatus`.
/// Goal pause/resume use `blocked` / `active`. No extra status is introduced.
public enum GoalMachine: Sendable {
    public static let terminal: Set<GoalStatus> = [.completed, .aborted]

    public static func nextStatus(
        _ status: GoalStatus,
        command: GoalCommand
    ) -> GoalStatus? {
        switch (status, command) {
        case (.proposed, .submit):
            return .proposed
        case (.proposed, .activate):
            return .active
        case (.proposed, .abort):
            return .aborted
        case (.active, .suspend):
            return .blocked
        case (.active, .complete):
            return .completed
        case (.active, .abort):
            return .aborted
        case (.blocked, .resume):
            return .active
        case (.blocked, .abort):
            return .aborted
        case (.blocked, .complete):
            return .completed
        default:
            return nil
        }
    }

    public static func eventKind(for command: GoalCommand) -> ExecutionEventKind {
        switch command {
        case .submit: return .goalSubmitted
        case .activate: return .goalActivated
        case .suspend: return .goalBlocked
        case .resume: return .goalActivated
        case .complete: return .goalCompleted
        case .abort: return .goalAborted
        }
    }
}
