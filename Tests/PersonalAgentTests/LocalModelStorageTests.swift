import Foundation
import Testing
import PAFoundation
import PAProviders
@testable import PAProvidersLocal

@Suite struct LocalModelStorageTests {
    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ModelStorageTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createValidGGUFFile(at url: URL) throws {
        var data = Data()
        // Magic 0x46554747 ("GGUF" in little endian)
        var magic: UInt32 = 0x46554747
        data.append(Data(bytes: &magic, count: 4))
        // Version 3
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: 4))
        // Tensor count 0
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: 8))
        // Metadata count 0
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: 8))

        try data.write(to: url)
    }

    private func createInvalidGGUFFile(at url: URL) throws {
        let data = "Not a GGUF file header content".data(using: .utf8)!
        try data.write(to: url)
    }

    @Test func testImportValidGGUFAndManagement() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceDir = tempDir.appendingPathComponent("Source")
        let storageDir = tempDir.appendingPathComponent("Storage")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let ggufURL = sourceDir.appendingPathComponent("test-model.gguf")
        try createValidGGUFFile(at: ggufURL)

        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: storageDir)

        // 1. Import
        let descriptor = try await storage.importModel(from: ggufURL, name: "Test Model")
        #expect(descriptor.name == "Test Model")
        #expect(descriptor.filename == "test-model.gguf")
        #expect(descriptor.formatVersion == 3)

        // 2. List
        let models = try await storage.listModels()
        #expect(models.count == 1)
        #expect(models.first?.id == descriptor.id)

        // 3. Active Model
        let activeID = try await storage.getActiveModelID()
        #expect(activeID == descriptor.id)

        let activeDesc = try await storage.getActiveModelDescriptor()
        #expect(activeDesc?.id == descriptor.id)

        // 4. Model Identity conversion
        let identity = descriptor.toModelIdentity(baseDirectoryURL: storageDir)
        #expect(identity.id == descriptor.id)
        #expect(identity.localURL != nil)
        #expect(FileManager.default.fileExists(atPath: identity.localURL!.path))

        // 5. Delete Model
        try await storage.deleteModel(id: descriptor.id)
        let modelsAfterDelete = try await storage.listModels()
        #expect(modelsAfterDelete.isEmpty)
        #expect(try await storage.getActiveModelID() == nil)
    }

    @Test func testImportInvalidGGUFHeader() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ggufURL = tempDir.appendingPathComponent("invalid.gguf")
        try createInvalidGGUFFile(at: ggufURL)

        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: tempDir.appendingPathComponent("Storage"))

        do {
            _ = try await storage.importModel(from: ggufURL, name: "Invalid Model")
            #expect(Bool(false), "Expected invalidGGUFHeader error")
        } catch let err as LocalModelStorageError {
            if case .invalidGGUFHeader = err {
                #expect(true)
            } else {
                Issue.record("Unexpected LocalModelStorageError: \(err)")
            }
        }
    }

    @Test func testImportNonExistentFile() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingURL = tempDir.appendingPathComponent("nonexistent.gguf")
        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: tempDir.appendingPathComponent("Storage"))

        do {
            _ = try await storage.importModel(from: missingURL, name: "Missing Model")
            #expect(Bool(false), "Expected unreadableFile error")
        } catch let err as LocalModelStorageError {
            if case .unreadableFile = err {
                #expect(true)
            } else {
                Issue.record("Unexpected LocalModelStorageError: \(err)")
            }
        }
    }

    @Test func testSelectNonExistentModel() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: tempDir)
        let fakeID = ModelID(rawValue: "gguf-fake")

        do {
            try await storage.selectActiveModel(id: fakeID)
            #expect(Bool(false), "Expected modelNotFound error")
        } catch let err as LocalModelStorageError {
            if case .modelNotFound(let id) = err {
                #expect(id == fakeID)
            } else {
                Issue.record("Unexpected error: \(err)")
            }
        }
    }
}
