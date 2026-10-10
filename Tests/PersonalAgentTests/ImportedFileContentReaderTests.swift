import XCTest
@testable import PAImportGateway

final class ImportedFileContentReaderTests: XCTestCase {
    func testReadsUTF8TextAndParsesQuotedCSV() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("data.csv")
        try "name,description\r\nagent,\"reads, safely\"\r\n".write(to: input, atomically: true, encoding: .utf8)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let record = try await store.importFile(from: input)
        let result = try await ImportedFileContentReader().read(record, from: store)
        XCTAssertEqual(result.format, .csv)
        XCTAssertEqual(result.csvRows, [["name", "description"], ["agent", "reads, safely"]])
    }

    func testReadsCommonSourceAndConfigurationFormatsAsPlainText() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let fixtures: [(String, String)] = [
            ("Agent.swift", "struct Agent { let ready = true }"),
            ("settings.toml", "mode = \"local\""),
            ("script.sh", "printf 'safe\\n'"),
            ("index.html", "<script>not executed</script><p>content</p>"),
            ("query.sql", "SELECT 1;")
        ]
        for (name, contents) in fixtures {
            let input = base.appendingPathComponent(name)
            try contents.write(to: input, atomically: true, encoding: .utf8)
            let record = try await store.importFile(from: input)
            let result = try await ImportedFileContentReader().read(record, from: store)
            XCTAssertEqual(result.format, .plainText, name)
            XCTAssertEqual(result.text, contents, name)
        }
    }

    func testRejectsMalformedJSONAndUnsupportedBinaryFormat() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let json = base.appendingPathComponent("bad.json")
        try "{broken".write(to: json, atomically: true, encoding: .utf8)
        let record = try await store.importFile(from: json)
        do {
            _ = try await ImportedFileContentReader().read(record, from: store)
            XCTFail("Malformed JSON must not be passed as parsed content")
        } catch let error as ImportedFileReaderError {
            XCTAssertEqual(error, .malformedJSON)
        }

        let pdf = base.appendingPathComponent("document.pdf")
        try Data("%PDF-1.7".utf8).write(to: pdf)
        let pdfRecord = try await store.importFile(from: pdf)
        do {
            _ = try await ImportedFileContentReader().read(pdfRecord, from: store)
            XCTFail("PDF must stay explicitly unsupported until a PDF reader exists")
        } catch let error as ImportedFileReaderError {
            #if canImport(PDFKit)
            XCTAssertTrue(error == .malformedDocument || error == .emptyExtraction || error == .unsupportedFormat("scanned PDF requires OCR"))
            #else
            XCTAssertEqual(error, .unsupportedFormat("pdf"))
            #endif
        }
    }

    func testRTFReaderIsNativeAndFailClosedWhenUnavailable() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("note.rtf")
        try #"{\rtf1\ansi Hello \b Agent\b0}"#.write(to: input, atomically: true, encoding: .utf8)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let record = try await store.importFile(from: input)
        #if canImport(Darwin)
        let result = try await ImportedFileContentReader().read(record, from: store)
        XCTAssertEqual(result.format, .richText)
        XCTAssertTrue(result.text.contains("Hello"))
        XCTAssertTrue(result.text.contains("Agent"))
        #else
        do {
            _ = try await ImportedFileContentReader().read(record, from: store)
            XCTFail("RTF must not claim extraction when the native reader is unavailable")
        } catch let error as ImportedFileReaderError {
            XCTAssertEqual(error, .unsupportedFormat("rtf"))
        }
        #endif
    }

    func testReadsXMLPropertyListAsValidatedText() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("settings.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>theme</key><string>dark</string></dict></plist>
        """.write(to: input, atomically: true, encoding: .utf8)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let record = try await store.importFile(from: input)
        let result = try await ImportedFileContentReader().read(record, from: store)
        XCTAssertEqual(result.format, .propertyList)
        XCTAssertTrue(result.text.contains("<key>theme</key>"))
        XCTAssertTrue(result.text.contains("<string>dark</string>"))
    }

    func testImageOCRCapabilityIsExplicit() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00]).write(to: input)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let record = try await store.importFile(from: input)
        do {
            _ = try await ImportedFileContentReader().read(record, from: store)
            XCTFail("Invalid image bytes must not produce successful OCR")
        } catch let error as ImportedFileReaderError {
            #if canImport(Vision) && canImport(ImageIO)
            XCTAssertEqual(error, .malformedDocument)
            #else
            XCTAssertEqual(error, .unsupportedFormat("png"))
            #endif
        }
    }

    func testEnforcesReadSizeLimitAndRejectsBinaryText() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = try ImportedFileStore(directoryURL: base.appendingPathComponent("store"))
        let large = base.appendingPathComponent("large.txt")
        try "123456".write(to: large, atomically: true, encoding: .utf8)
        let largeRecord = try await store.importFile(from: large)
        do {
            _ = try await ImportedFileContentReader(maximumReadableBytes: 4).read(largeRecord, from: store)
            XCTFail("Reader must enforce its independent memory bound")
        } catch let error as ImportedFileReaderError {
            XCTAssertEqual(error, .fileTooLarge(limitBytes: 4))
        }

        let binary = base.appendingPathComponent("binary.txt")
        try Data([0x41, 0x00, 0x42]).write(to: binary)
        let binaryRecord = try await store.importFile(from: binary)
        do {
            _ = try await ImportedFileContentReader().read(binaryRecord, from: store)
            XCTFail("Binary payload must not be interpreted as text")
        } catch let error as ImportedFileReaderError {
            XCTAssertEqual(error, .binaryContent)
        }
    }
}
