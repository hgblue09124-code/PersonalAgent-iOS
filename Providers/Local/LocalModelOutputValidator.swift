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

        // Keep terminators attached to each sentence: the de-duplication rules below
        // need punctuation to distinguish a generic question from a normal statement.
        var sentences: [String] = []
        var sentenceStart = normalized.startIndex
        for index in normalized.indices where ".?!".contains(normalized[index]) {
            let end = normalized.index(after: index)
            let sentence = normalized[sentenceStart..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            sentenceStart = end
        }
        if sentenceStart < normalized.endIndex {
            let tail = normalized[sentenceStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { sentences.append(tail) }
        }
        guard sentences.count >= 2 else { return normalized }

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
            let previousIsGenericHelpQuestion = previous.hasSuffix("?") && [
                "bạn muốn tôi giúp",
                "bạn muốn tôi hỗ trợ",
                "how can i help",
                "what can i help"
            ].contains(where: { previous.lowercased().hasPrefix($0) })
            let currentIsMoreSpecificQuestion = sentence.hasSuffix("?")
                && currentTokens.count >= previousTokens.count + 3

            if similarity >= 0.7
                || (previousIsGenericHelpQuestion && currentIsMoreSpecificQuestion) {
                collapsed = true
                // Keep the more informative variant instead of letting a shorter
                // trailing paraphrase overwrite the intended response.
                if currentTokens.count > previousTokens.count {
                    kept[kept.count - 1] = sentence
                }
            } else {
                kept.append(sentence)
            }
        }

        if collapsed {
            return kept.map { sentence in
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let last = trimmed.last, ".?!".contains(last) else {
                    return trimmed + "."
                }
                return trimmed
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
