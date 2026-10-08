import Foundation

/// Pure production output boundary for local model generation.
public enum LocalModelOutputValidator {
    /// Removes transport artifacts and collapses an accidental repeated block at the end
    /// of a response before the text reaches the product UI.
    public static func sanitize(text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let words = normalized.split { $0.isWhitespace }.map(String.init)
        guard words.count >= 8 else { return normalized }

        let maxBlockSize = min(24, words.count / 2)
        if maxBlockSize >= 3 {
            for blockSize in stride(from: maxBlockSize, through: 3, by: -1) {
                let block = Array(words.suffix(blockSize))
                var repeatCount = 1
                var cursor = words.count - blockSize

                while cursor >= blockSize {
                    let candidate = Array(words[(cursor - blockSize)..<cursor])
                    guard candidate == block else { break }
                    repeatCount += 1
                    cursor -= blockSize
                }

                if repeatCount >= 2 {
                    let prefix = Array(words.prefix(cursor))
                    return (prefix + block).joined(separator: " ")
                }
            }
        }

        return normalized
    }

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
