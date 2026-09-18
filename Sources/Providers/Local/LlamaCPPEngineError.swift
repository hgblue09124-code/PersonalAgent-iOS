import Foundation

/// Explicit typed errors emitted during local llama.cpp engine operations.
public enum LlamaCPPEngineError: Error, Sendable, Equatable, LocalizedError {
    case invalidModelURL
    case modelFileNotFound(URL)
    case invalidGGUFHeader(String)
    case modelNotLoaded
    case modelAlreadyLoaded
    case loadFailed(String)
    case generationFailed(String)
    case cancelled
    case thermalStateCritical
    case memoryPressureCritical
    case residencyViolation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidModelURL:
            return "Invalid model URL provided."
        case .modelFileNotFound(let url):
            return "Model file not found at URL: \(url.path)."
        case .invalidGGUFHeader(let reason):
            return "Invalid GGUF header: \(reason)."
        case .modelNotLoaded:
            return "Local model engine is not loaded."
        case .modelAlreadyLoaded:
            return "Local model engine is already loaded."
        case .loadFailed(let reason):
            return "Failed to load model: \(reason)."
        case .generationFailed(let reason):
            return "Generation failed: \(reason)."
        case .cancelled:
            return "Generation was cancelled."
        case .thermalStateCritical:
            return "Execution aborted due to critical device thermal state."
        case .memoryPressureCritical:
            return "Execution aborted due to critical device memory pressure."
        case .residencyViolation(let reason):
            return "Residency violation: \(reason)."
        }
    }
}
