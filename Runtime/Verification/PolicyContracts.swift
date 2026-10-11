import PAKernel

/// Default runtime policy is deliberately least-privilege.
/// Sensitive capabilities require an explicitly configured policy.
public struct DefaultPolicyEvaluator: PolicyEvaluating {
    public init() {}

    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        if intent.capabilities.isEmpty || intent.capabilities == .read {
            return .allow("Read-only action")
        }
        return .deny("Explicit capability grant required")
    }
}
