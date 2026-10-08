import Foundation

/// Pure production output boundary for local model generation.
public enum LocalModelOutputValidator {
    /// Removes transport artifacts and collapses accidental repeated blocks or near-duplicate
    /// sentences before the text reaches the product UI.
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

        let sentenceParts = normalized.split(
            whereSeparator: { $0 == "." || $0 == "?" || $0 == "!" }
        )
        guard sentenceParts.count >= 2 else { return normalized }

        let sentences = sentenceParts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var kept: [String] = []
        var collapsed = false

        for sentence in sentences {
            guard let previous = kept.last else {
                kept.append(sentence)
                continue
            }

            let previousTokens = Set(previous.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let currentTokens = Set(sentence.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            guard !previousTokens.isEmpty, !currentTokens.isEmpty else {
                kept.append(sentence)
                continue
            }

            let intersection = previousTokens.intersection(currentTokens).count
            let union = previousTokens.union(currentTokens).count
            let similarity = Double(intersection) / Double(union)

            if similarity >= 0.7 {
                collapsed = true
                if currentTokens.count > previousTokens.count {
                    kept[kept.count - 1] = sentence
                }
            } else {
                kept.append(sentence)
            }
        }

        if collapsed {
            return kept.map { sentence in
                if let question = sentences.first(where: { $0 == sentence }) {
                    let original = normalized.range(of: question)
                    if let original {
                        let end = normalized[original.upperBound...].first
                        if end == "?" || end == "!" {
                            return sentence + String(end!)
                        }
                    }
                }
                return sentence + "."
            }.joined(separator: " ")
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
