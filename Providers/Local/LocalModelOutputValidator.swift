import Foundation

/// Pure production output boundary for local model generation.
public enum LocalModelOutputValidator {
    /// Removes transport artifacts and collapses an accidental repeated block at the end
    /// of a response before the text reaches the product UI.
()=>nb
    /// Validates generation completion output. Throws emptyOutput if text is empty
    /// or the engine reports that no tokens were generated.
    public static func validate(text: String, generatedCount: Int? = nil) throws {
        if let count = generatedCount, count == 0 {
            throw LlamaCPPEngineError.emptyOutput
        }
        if sanitize(text: text).isEmpty {
            throw LlamaCPPEngineError.emptyOutput
        }
    }
}
