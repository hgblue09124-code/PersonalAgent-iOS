import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision) && canImport(ImageIO)
import Vision
import ImageIO
import CoreGraphics
#endif

public enum ImportedContentFormat: String, Codable, Sendable, Equatable {
    case plainText
    case markdown
    case json
    case csv
    case yaml
    case log
    case pdf
    case imageOCR
    case propertyList
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
    case malformedDocument
    case extractionLimitExceeded
    case emptyExtraction
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

        let ext = importedFile.fileExtension.lowercased()
        if ext == "plist" || ext == "strings" {
            return try readPropertyList(importedFile, url: url)
        }
        if ext == "pdf" {
            #if canImport(PDFKit)
            return try readPDF(importedFile, url: url)
            #else
            throw ImportedFileReaderError.unsupportedFormat(ext)
            #endif
        }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp"].contains(ext) {
            #if canImport(Vision) && canImport(ImageIO)
            return try readImageOCR(importedFile, url: url)
            #else
            throw ImportedFileReaderError.unsupportedFormat(ext)
            #endif
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
        switch ext {
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
        case "pdf":
            throw ImportedFileReaderError.unsupportedFormat(ext)
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

    private func readPropertyList(_ importedFile: ImportedFile, url: URL) throws -> ImportedFileContent {
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch { throw ImportedFileReaderError.missingFile }
        var sourceFormat = PropertyListSerialization.PropertyListFormat.xml
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: &sourceFormat)
        } catch {
            throw ImportedFileReaderError.malformedDocument
        }
        let xml: Data
        do {
            xml = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        } catch {
            throw ImportedFileReaderError.malformedDocument
        }
        guard let text = String(data: xml, encoding: .utf8) else {
            throw ImportedFileReaderError.invalidUTF8
        }
        guard text.utf8.count <= 4 * 1024 * 1024 else {
            throw ImportedFileReaderError.extractionLimitExceeded
        }
        return ImportedFileContent(fileID: importedFile.id, format: .propertyList, text: text)
    }

    #if canImport(PDFKit)
    private func readPDF(_ importedFile: ImportedFile, url: URL) throws -> ImportedFileContent {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw ImportedFileReaderError.malformedDocument
        }
        guard document.pageCount <= 500 else {
            throw ImportedFileReaderError.extractionLimitExceeded
        }
        var pages: [String] = []
        var extractedBytes = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw ImportedFileReaderError.malformedDocument
            }
            let text = page.string ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(text)
                extractedBytes += text.utf8.count
            } else {
                #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
                guard index < 50 else {
                    throw ImportedFileReaderError.extractionLimitExceeded
                }
                let scannedText = try recognizePDFPage(page)
                if !scannedText.isEmpty {
                    pages.append(scannedText)
                    extractedBytes += scannedText.utf8.count
                }
                #endif
            }
            guard extractedBytes <= 4 * 1024 * 1024 else {
                throw ImportedFileReaderError.extractionLimitExceeded
            }
        }
        guard !pages.isEmpty else {
            throw ImportedFileReaderError.emptyExtraction
        }
        return ImportedFileContent(
            fileID: importedFile.id,
            format: .pdf,
            text: pages.joined(separator: "\n\n")
        )
    }
    #if canImport(PDFKit) && canImport(Vision) && canImport(CoreGraphics)
    /// Rasterizes one scanned page within a strict pixel budget before OCR.
    private func recognizePDFPage(_ page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            throw ImportedFileReaderError.malformedDocument
        }
        let scale = min(2.0, 2_000.0 / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= 4_000_000,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = renderPDFPage(page, in: context, width: width, height: height) else {
            throw ImportedFileReaderError.extractionLimitExceeded
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw ImportedFileReaderError.malformedDocument
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private func renderPDFPage(_ page: PDFPage, in context: CGContext, width: Int, height: Int) -> CGImage? {
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / page.bounds(for: .mediaBox).width,
                        y: -CGFloat(height) / page.bounds(for: .mediaBox).height)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }
    #endif

    #if canImport(Vision) && canImport(ImageIO)
    private func readImageOCR(_ importedFile: ImportedFile, url: URL) throws -> ImportedFileContent {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value else {
            throw ImportedFileReaderError.malformedDocument
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, pixels <= 100_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportedFileReaderError.extractionLimitExceeded
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw ImportedFileReaderError.malformedDocument
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let extracted = lines.joined(separator: "\n")
        guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportedFileReaderError.emptyExtraction
        }
        guard extracted.utf8.count <= 4 * 1024 * 1024 else {
            throw ImportedFileReaderError.extractionLimitExceeded
        }
        return ImportedFileContent(fileID: importedFile.id, format: .imageOCR, text: extracted)
    }
    #endif

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
