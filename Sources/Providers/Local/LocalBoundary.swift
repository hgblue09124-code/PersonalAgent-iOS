import PAFoundation
import PAProviders

/// Reserved M2 boundary for Ollama, LM Studio, llama.cpp, vLLM, custom local endpoints.
public enum LocalProviderBoundary {
    public static let providerID = ProviderID(rawValue: "local")
    public static let availableInMilestone = "M2"
    public static let intendedCompatibleServers = [
        "ollama",
        "lmstudio",
        "llama.cpp",
        "vllm",
        "custom",
    ]
}
