import Foundation

public enum ImportedContentFormat: String, Codable, Sendable, Equatable {
    case plainText
    case markdown
    case json
    case csv
    case yaml
    case log
}

public struct ImportedFileContent: Sendable, Equatable {
    public let fileID: UUID
    public let format: ImportedContentFormat
    public let text: String
    public let csvRows: [[String]]?

    public init(fileID: UUID, format: ImportedContentFormat, text: String, csvRows: [[String]]? = nil) {
        self.fileID = fileID
        self.format = format
        self.text = text
        self.csvRows = csvRows
    }
}

public enum ImportedFileReaderError: Error, Sendable, Equatable {
    case unsupportedFormat(String)
    case fileTooLarge(limitBytes: Int64)
    case missingFile
    case fileChanged
    case invalidUTF8
    case binaryContent
    case malformedJSON
    case malformedCSV
}

/// Bounded, non-executing readers for common text formats. Extensions select a
/// candidate reader, but the reader also validates bytes/structure before accepting
/// content. Imported content remains untrusted input and must not be treated as policy.
public struct ImportedFileContentReader: Sendable {
    public static let defaultMaximumReadableBytes: Int64 = 8 * 1024 * 1024
    private let maximumReadableBytes: Int64

    public init(maximumReadableBytes: Int64 = ImportedFileContentReader.defaultMaximumReadableBytes) {
        self.maximumReadableBytes = max(0, maximumReadableBytes)
    }

    public func read(_ importedFile: ImportedFile, from store: ImportedFileStore) async throws -> ImportedFileContent {
        guard let url = await store.fileURL(for: importedFile.id) else {
            throw ImportedFileReaderError.missingFile
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw ImportedFileReaderError.missingFile
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ImportedFileReaderError.missingFile
        }
        guard let actualSize = (attributes[.size] as? NSNumber)?.int64Value,
              actualSize == importedFile.sizeBytes else {
            throw ImportedFileReaderError.fileChanged
        }
        guard actualSize <= maximumReadableBytes else {
            throw ImportedFileReaderError.fileTooLarge(limitBytes: maximumReadableBytes)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ImportedFileReaderError.missingFile
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ImportedFileReaderError.invalidUTF8
        }
        let text = decoded.hasPrefix("\u{FEFF}") ? String(decoded.dropFirst()) : decoded
        guard !text.unicodeScalars.contains(where: { scalar in
            scalar.value == 0 || (scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D && scalar.value != 0x0C)
        }) else {
            throw ImportedFileReaderError.binaryContent
        }

        let format: ImportedContentFormat
        switch importedFile.fileExtension.lowercased() {
        case "txt", "text":
            format = .plainText
        case "md", "markdown", "mdown":
            format = .markdown
        case "json", "jsonl", "ndjson":
            guard Self.isValidJSON(text, extension: importedFile.fileExtension.lowercased()) else {
                throw ImportedFileReaderError.malformedJSON
            }
            format = .json
        case "csv", "tsv":
            format = .csv
        case "yaml", "yml":
            format = .yaml
        case "log":
            format = .log
        default:
            throw ImportedFileReaderError.unsupportedFormat(importedFile.fileExtension)
        }

        let rows: [[String]]?
        if format == .csv {
            rows = try Self.parseDelimited(text, delimiter: importedFile.fileExtension.lowercased() == "tsv" ? "\t" : ",")
        } else {
            rows = nil
        }
        return ImportedFileContent(fileID: importedFile.id, format: format, text: text, csvRows: rows)
    }

    private static func isValidJSON(_ text: String, extension ext: String) -> Bool {
        if ext == "jsonl" || ext == "ndjson" {
            let lines = text.split(whereSeparator: \.isNewline)
            return !lines.isEmpty && lines.allSatisfy { line in
                guard let data = String(line).data(using: .utf8) else { return false }
                return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
            }
        }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private static func parseDelimited(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                guard field.isEmpty else { throw ImportedFileReaderError.malformedCSV }
                quoted = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\n" { index = next }
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        guard !quoted else { throw ImportedFileReaderError.malformedCSV }
        let endsWithLineBreak = text.last.map { $0 == "\n" || $0 == "\r" || $0 == "\r\n" } ?? false
        if !field.isEmpty || !row.isEmpty || text.isEmpty || !endsWithLineBreak {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
