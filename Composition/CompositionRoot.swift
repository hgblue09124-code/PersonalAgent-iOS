import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability

/// The only surface UI is allowed to hold.
/// M0 exposes availability, not a running agent.
public protocol CompositionRoot: Sendable {
    var milestone: MilestoneGate { get }
    var logger: any AgentLogger { get }
}

public struct M0CompositionRoot: CompositionRoot {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger

    public init(logger: any AgentLogger = NullLogger()) {
        self.milestone = .m0
        self.logger = logger
    }
}

public struct NullLogger: AgentLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
