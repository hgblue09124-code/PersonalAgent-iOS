import PAPolicy
import PACognition
import PAAgency
import PAProviders

/// Seams for later milestones. M1/M2 do not invoke cognition through these ports.
/// The provider port holds the contract, never a concrete adapter type.
public struct KernelCoordinationBoundary: Sendable {
    public var policy: (any PolicyEvaluating)?
    public var planner: (any Planning)?
    public var executor: (any Executing)?
    public var agency: (any AgencyLooping)?
    public var provider: (any LLMProvider)?

    public init(
        policy: (any PolicyEvaluating)? = nil,
        planner: (any Planning)? = nil,
        executor: (any Executing)? = nil,
        agency: (any AgencyLooping)? = nil,
        provider: (any LLMProvider)? = nil
    ) {
        self.policy = policy
        self.planner = planner
        self.executor = executor
        self.agency = agency
        self.provider = provider
    }

    public var isWiredForCognition: Bool {
        planner != nil || executor != nil || agency != nil
    }

    public var isWiredForProvider: Bool {
        provider != nil
    }
}
