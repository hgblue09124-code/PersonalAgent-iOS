import Foundation
import Testing
import PAImportGateway

@Suite("Universal Import Gateway")
struct ImportedFileStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func importsArbitraryExtensionAndPersistsAcrossStoreRecreation() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.custom-format")
        let payload = Data("format agnostic intake".utf8)
        try payload.write(to: source)

        let store = try ImportedFileStore(directoryURL: root.appendingPathComponent("Inbox"))
        let record = try await store.importFile(from: source, contentTypeIdentifier: "public.data")
        #expect(record.originalName == "report.custom-format")
        #expect(record.fileExtension == "custom-format")
        #expect(record.sizeBytes == Int64(payload.count))
        let storedURL = try #require(await store.fileURL(for: record.id))
        #expect(try Data(contentsOf: storedURL) == payload)

        let reopened = try ImportedFileStore(directoryURL: root.appendingPathComponent("Inbox"))
        #expect(await reopened.listImports() == [record])
    }

    @Test func rejectsDirectoriesAndOversizedFiles() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("large.bin")
        try Data(repeating: 1, count: 128).write(to: source)
        let store = try ImportedFileStore(directoryURL: root.appendingPathComponent("Inbox"), maximumFileSize: 32)

        do {
            _ = try await store.importFile(from: folder)
            Issue.record("Directories must not be imported as ordinary files")
        } catch let error as ImportGatewayError {
            #expect(error == .sourceIsNotAFile)
        }

        do {
            _ = try await store.importFile(from: source)
            Issue.record("Oversized files must be rejected")
        } catch let error as ImportGatewayError {
            #expect(error == .fileTooLarge(limitBytes: 32))
        }
        #expect(await store.listImports().isEmpty)
    }

    @Test func removeDeletesBothMetadataAndStoredPayload() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("payload.bin")
        try Data([1, 2, 3, 4]).write(to: source)
        let store = try ImportedFileStore(directoryURL: root.appendingPathComponent("Inbox"))
        let record = try await store.importFile(from: source)
        let storedURL = try #require(await store.fileURL(for: record.id))
        try await store.removeImport(id: record.id)
        #expect(await store.listImports().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
    }
}
