
public enum AgentError: Error, Sendable, Equatable {
    case unavailable(milestone: String, capability: String)
    case policyDenied(reason: String)
    case approvalRequired(actionID: ActionID)
    case providerUnavailable(ProviderID)
    case invalidContract(String)
    case persistence(String)
    case cancelled
}
