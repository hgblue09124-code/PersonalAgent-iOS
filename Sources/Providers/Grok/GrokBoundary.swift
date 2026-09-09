import PAFoundation
import PAProviders

/// Reserved M2 boundary. No network client in M0.
public enum GrokProviderBoundary {
    public static let providerID = ProviderID(rawValue: "grok")
    public static let availableInMilestone = "M2"
}
