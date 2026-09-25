import PAFoundation

/// Structured logging surface. Production code must not use `print()`.
public protocol AgentLogger: Sendable {
    func log(_ event: LogEvent)
}

public struct LogEvent: Sendable, Equatable {
    public let level: LogLevel
    public let category: String
    public let message: String
    public let metadata: [String: String]

    public init(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}

public enum LogLevel: String, Sendable, Codable {
    case debug
    case info
    case warning
    case error
}

public protocol AgentPhaseObserving: Sendable {
    func phaseDidChange(_ phase: AgentPhase) async
}
