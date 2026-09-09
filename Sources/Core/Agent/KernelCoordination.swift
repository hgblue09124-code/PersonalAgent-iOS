import PAPolicy
import PACognition
import PAAgency
import PAProviders
import PAModules

/// Seams for later milestones. Concrete modules/providers stay outside Kernel sources.
public struct KernelCoordinationBoundary: Sendable {
    public var policy: (any PolicyEvaluating)?
    public var planner: (any Planning)?
    public var executor: (any Executing)?
    public var agency: (any AgencyLooping)?
    public var provider: (any LLMProvider)?
    public var modules: (any ModuleExecuting)?

    public init(
        policy: (any PolicyEvaluating)? = nil,
        planner: (any Planning)? = nil,
        executor: (any Executing)? = nil,
        agency: (any AgencyLooping)? = nil,
        provider: (any LLMProvider)? = nil,
        modules: (any ModuleExecuting)? = nil
    ) {
        self.policy = policy
        self.planner = planner
        self.executor = executor
        self.agency = agency
        self.provider = provider
        self.modules = modules
    }

    public var isWiredForCognition: Bool {
        planner != nil || executor != nil || agency != nil
    }

    public var isWiredForProvider: Bool {
        provider != nil
    }

    public var isWiredForModules: Bool {
        modules != nil
    }
}
