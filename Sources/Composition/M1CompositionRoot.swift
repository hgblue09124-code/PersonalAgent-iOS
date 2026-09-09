import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents

/// Wires an authoritative kernel. Does not own UI or a provider.
public struct M1CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let eventLog: InMemoryEventLog

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal"),
        logger: any AgentLogger = NullLogger()
    ) async {
        let log = InMemoryEventLog()
        self.milestone = .m1
        self.logger = logger
        self.eventLog = log
        self.runtime = await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger
        )
    }
}
