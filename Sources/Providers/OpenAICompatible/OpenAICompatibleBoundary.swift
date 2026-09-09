import PAFoundation
import PAProviders

/// Reserved M2 boundary for any OpenAI-compatible HTTP server.
public enum OpenAICompatibleProviderBoundary {
    public static let providerID = ProviderID(rawValue: "openai-compatible")
    public static let availableInMilestone = "M2"
}
