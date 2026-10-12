import Foundation
import XCTest
import PAImportGateway

final class ImportedFileStoreRegressionTests: XCTestCase {
    func testImportCopiesBytesAndSurvivesStoreReopen() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeRoot = temporaryRoot.appendingPathComponent("library", isDirectory: true)
        let sourceURL = temporaryRoot.appendingPathComponent("sample.txt")
        let expected = Data("PersonalAgent import regression".utf8)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try expected.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = try ImportedFileStore(directoryURL: storeRoot)
        let record = try await store.importFile(from: sourceURL, contentTypeIdentifier: "public.plain-text")

        XCTAssertEqual(record.originalName, "sample.txt")
        XCTAssertEqual(record.sizeBytes, Int64(expected.count))
        let storedURL = try XCTUnwrap(await store.fileURL(for: record.id))
        XCTAssertEqual(try Data(contentsOf: storedURL), expected)

        let reopenedStore = try ImportedFileStore(directoryURL: storeRoot)
        let records = await reopenedStore.listImports()
        XCTAssertEqual(records, [record])
        let reopenedURL = try XCTUnwrap(await reopenedStore.fileURL(for: record.id))
        XCTAssertEqual(try Data(contentsOf: reopenedURL), expected)
    }

    func testImportRejectsMissingSourceWithoutCreatingRecord() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeRoot = temporaryRoot.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = try ImportedFileStore(directoryURL: storeRoot)
        do {
            _ = try await store.importFile(from: temporaryRoot.appendingPathComponent("missing.txt"))
            XCTFail("Import should fail for a missing source.")
        } catch {
            XCTAssertFalse(error is ImportGatewayError && error as? ImportGatewayError == .sourceIsNotAFile)
        }
        XCTAssertTrue(await store.listImports().isEmpty)
    }
}
