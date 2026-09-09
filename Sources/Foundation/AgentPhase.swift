
/// Observable agent phase. UI may render this. UI may not set internals.
public enum AgentPhase: String, Sendable, Codable, CaseIterable {
    case idle
    case thinking
    case planning
    case executing
    case waitingForApproval
    case syncing
    case failed
    case completed
}
