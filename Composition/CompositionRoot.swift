import PAFoundation
import PAKernel
import PAObservability

public struct MilestoneGate: Sendable, Equatable {
    public let milestone: String
    public let kernelRuntime: Bool
    public let providers: Bool
    public let storageEngine: Bool
    public let memoryEngine: Bool
    public let skillRuntime: Bool
    public let toolRuntime: Bool
    public let cognitionLoop: Bool
    public let eventReplay: Bool

    public static let m0 = MilestoneGate(
        milestone: "M0",
        kernelRuntime: false,
        providers: false,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m1 = MilestoneGate(
        milestone: "M1",
        kernelRuntime: true,
        providers: false,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m2 = MilestoneGate(
        milestone: "M2",
        kernelRuntime: true,
        providers: true,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m3 = MilestoneGate(
        milestone: "M3",
        kernelRuntime: true,
        providers: true,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m4 = MilestoneGate(
        milestone: "M4",
        kernelRuntime: true,
        providers: true,
        storageEngine: true,
        memoryEngine: true,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m6 = MilestoneGate(
        milestone: "M6",
        kernelRuntime: true,
        providers: true,
        storageEngine: true,
        memoryEngine: true,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: true,
        eventReplay: false
    )

    public static let m7 = MilestoneGate(
        milestone: "M7",
        kernelRuntime: true,
        providers: true,
        storageEngine: true,
        memoryEngine: true,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: true,
        eventReplay: false
    )

    public static let m8 = MilestoneGate(
        milestone: "M8",
        kernelRuntime: true,
        providers: true,
        storageEngine: true,
        memoryEngine: true,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: true,
        eventReplay: false
    )
}
}

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
