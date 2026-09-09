import PAPolicy
import PACognition
import PAAgency

/// Seams for later milestones. M1 does not invoke these ports.
public struct KernelCoordinationBoundary: Sendable {
    public var policy: (any PolicyEvaluating)?
    public var planner: (any Planning)?
    public var executor: (any Executing)?
    public var agency: (any AgencyLooping)?

    public init(
        policy: (any PolicyEvaluating)? = nil,
        planner: (any Planning)? = nil,
        executor: (any Executing)? = nil,
        agency: (any AgencyLooping)? = nil
    ) {
        self.policy = policy
        self.planner = planner
        self.executor = executor
        self.agency = agency
    }

    public var isWiredForCognition: Bool {
        planner != nil || executor != nil || agency != nil
    }
}
