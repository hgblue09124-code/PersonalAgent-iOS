import Foundation

/// Pure production output validator enforcing that local model generation produces non-empty, non-zero-token results.
public enum LocalModelOutputValidator {
    /// Validates generation completion output. Throws `LlamaCPPEngineError.emptyOutput` if text is empty or generated token count is 0.
    public static func validate(text: String, generatedCount: Int? = nil) throws {
        if let count = generatedCount, count == 0 {
            throw LlamaCPPEngineError.emptyOutput
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LlamaCPPEngineError.emptyOutput
        }
    }
}
