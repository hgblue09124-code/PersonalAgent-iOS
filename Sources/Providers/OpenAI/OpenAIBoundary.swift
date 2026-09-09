import PAFoundation
import PAProviders

/// Reserved M2 boundary. No network client in M0.
public enum OpenAIProviderBoundary {
    public static let providerID = ProviderID(rawValue: "openai")
    public static let availableInMilestone = "M2"
}
