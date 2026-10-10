import PAKernel

/// Default runtime policy implementation. Replace with configured policy in production.
public struct DefaultPolicyEvaluator: PolicyEvaluating {
    public init() {}

    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .allow("Default policy permit")
    }
}
