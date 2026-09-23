import Foundation
import Testing
import PAFoundation
import PAProviders
import PAProvidersLocal
import PAComposition

@Suite("Local Model Storage & Selection Tests")
struct LocalModelStorageTests {

    private func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createValidGGUFFile(at directory: URL, filename: String = "test-model.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        var data = Data()

        // 1. Magic bytes 0x46554747 ("GGUF" in LE)
        let magic: UInt32 = 0x46554747
        var magicLE = magic.littleEndian
        data.append(Data(bytes: &magicLE, count: 4))

        // 2. Version UInt32 = 3
        let version: UInt32 = 3
        var versionLE = version.littleEndian
        data.append(Data(bytes: &versionLE, count: 4))

        // 3. Tensor count UInt64 = 10
        let tensorCount: UInt64 = 10
        var tensorCountLE = tensorCount.littleEndian
        data.append(Data(bytes: &tensorCountLE, count: 8))

        // 4. Metadata count UInt64 = 0
        let metadataCount: UInt64 = 0
        var metadataCountLE = metadataCount.littleEndian
        data.append(Data(bytes: &metadataCountLE, count: 8))

        // Dummy payload to make file non-empty
        data.append(Data(repeating: 0x00, count: 1024))

        try data.write(to: fileURL)
        return fileURL
    }

    private func createInvalidGGUFFile(at directory: URL, filename: String = "bad-model.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        let badData = Data("NOT_GGUF_HEADER_DATA_1234567890".utf8)
        try badData.write(to: fileURL)
        return fileURL
    }

    private func createUnsupportedVersionGGUFFile(at directory: URL, filename: String = "v1-model.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        var data = Data()

        // Magic bytes 0x46554747
        let magic: UInt32 = 0x46554747
        var magicLE = magic.littleEndian
        data.append(Data(bytes: &magicLE, count: 4))

        // Unsupported Version UInt32 = 1
        let version: UInt32 = 1
        var versionLE = version.littleEndian
        data.append(Data(bytes: &versionLE, count: 4))

        // Tensor count UInt64 = 1
        let tensorCount: UInt64 = 1
        var tensorCountLE = tensorCount.littleEndian
        data.append(Data(bytes: &tensorCountLE, count: 8))

        // Metadata count UInt64 = 0
        let metadataCount: UInt64 = 0
        var metadataCountLE = metadataCount.littleEndian
        data.append(Data(bytes: &metadataCountLE, count: 8))

        try data.write(to: fileURL)
        return fileURL
    }

    @Test func testImportValidGGUFModelCopiesFileAndPersistsMetadata() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = try createValidGGUFFile(at: root, filename: "source-llama.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: sourceURL, name: "Test Llama Model")

        #expect(descriptor.name == "Test Llama Model")
        #expect(descriptor.version == 3)
        #expect(descriptor.tensorCount == 10)
        #expect(descriptor.fileSizeBytes > 0)

        // Verify model file copied into app storage
        let models = try await storage.listModels()
        #expect(models.count == 1)
        #expect(models.first?.id == descriptor.id)

        let fileURL = try await storage.modelFileURL(for: descriptor.id)
        #expect(fileURL != nil)
        #expect(fileURL != sourceURL) // Ensures copied into app storage
        #expect(FileManager.default.fileExists(atPath: fileURL!.path))
    }

    @Test func testImportInvalidGGUFMagicBytesFailsAndLeavesNoOrphanFile() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let badSource = try createInvalidGGUFFile(at: root, filename: "corrupt.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        await #expect(throws: LocalModelStorageError.self) {
            try await storage.importModel(from: badSource, name: "Corrupt Model")
        }

        let models = try await storage.listModels()
        #expect(models.isEmpty)

        // Verify no orphan files created in storageDir
        let contents = try FileManager.default.contentsOfDirectory(atPath: storageDir.path)
            .filter { $0 != "models_index.json" }
        #expect(contents.isEmpty)
    }

    @Test func testImportUnsupportedGGUFVersionFailsAndLeavesNoOrphanFile() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let v1Source = try createUnsupportedVersionGGUFFile(at: root, filename: "v1.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        await #expect(throws: LocalModelStorageError.self) {
            try await storage.importModel(from: v1Source, name: "V1 Model")
        }

        let models = try await storage.listModels()
        #expect(models.isEmpty)

        let contents = try FileManager.default.contentsOfDirectory(atPath: storageDir.path)
            .filter { $0 != "models_index.json" }
        #expect(contents.isEmpty)
    }

    @Test func testActiveModelSelectionAndDescriptorResolution() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "active-test.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)

        let model1 = try await storage.importModel(from: source, name: "Model 1")

        try await storage.setActiveModel(id: model1.id)

        let activeID = try await storage.activeModelID()
        let activeDescriptor = try await storage.activeModelDescriptor()

        #expect(activeID == model1.id)
        #expect(activeDescriptor?.id == model1.id)
        #expect(activeDescriptor?.name == "Model 1")

        // Clearing active model
        try await storage.setActiveModel(id: nil)
        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)
    }

    @Test func testSetActiveModelToNonExistentIDThrowsModelNotFound() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storageDir = root.appendingPathComponent("ModelsStorage")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let bogusID = ModelID(rawValue: "non-existent-model-id")

        await #expect(throws: LocalModelStorageError.self) {
            try await storage.setActiveModel(id: bogusID)
        }
    }

    @Test func testDeleteModelRemovesFileClearsActiveSelectionAndIndex() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "delete-test.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let model = try await storage.importModel(from: source, name: "To Delete")
        try await storage.setActiveModel(id: model.id)

        #expect(try await storage.activeModelID() == model.id)

        let fileURL = try await storage.modelFileURL(for: model.id)
        #expect(fileURL != nil)
        #expect(FileManager.default.fileExists(atPath: fileURL!.path))

        try await storage.deleteModel(id: model.id)

        // Verify index cleared
        let models = try await storage.listModels()
        #expect(models.isEmpty)

        // Verify active selection cleared safely
        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)

        // Verify file deleted from disk
        #expect(!FileManager.default.fileExists(atPath: fileURL!.path))
    }

    @Test func testIndexPersistenceAcrossStorageInstances() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "persist-test.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")

        var importedID: ModelID?
        do {
            let storage1 = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)
            let m = try await storage1.importModel(from: source, name: "Persisted Model")
            try await storage1.setActiveModel(id: m.id)
            importedID = m.id
        }

        // Create fresh storage instance pointing to same directory
        let storage2 = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)
        let models = try await storage2.listModels()

        #expect(models.count == 1)
        #expect(models.first?.id == importedID)
        #expect(try await storage2.activeModelID() == importedID)
        #expect(try await storage2.activeModelDescriptor()?.name == "Persisted Model")
    }

    @Test func testM8CompositionRootWiresLocalModelStorage() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let composition = try await M8CompositionRoot(storeDirectoryURL: root)

        let models = try await composition.localModelStorage.listModels()
        #expect(models.isEmpty)
        #expect(try await composition.localModelStorage.activeModelID() == nil)
    }

    private final class UnremovableFileManager: FileManager, @unchecked Sendable {
        override func removeItem(at URL: URL) throws {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSURLErrorKey: URL])
        }
    }

    @Test func testDeleteModelFailsClosedWhenFileRemovalFails() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "fail-delete.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir, fileManager: UnremovableFileManager())

        let model = try await storage.importModel(from: source, name: "Fail Delete Model")
        try await storage.setActiveModel(id: model.id)

        let fileURL = try await storage.modelFileURL(for: model.id)
        #expect(fileURL != nil)

        do {
            try await storage.deleteModel(id: model.id)
            #expect(Bool(false), "Expected deleteModel to throw when file manager removeItem fails")
        } catch {
            // Expected failure
        }

        // Verify descriptor and activeModelID stay intact (fail closed)
        let models = try await storage.listModels()
        #expect(models.count == 1)
        #expect(models.first?.id == model.id)
        let activeID = try await storage.activeModelID()
        #expect(activeID == model.id)
    }

    @Test func testActiveModelDescriptorReconcilesSafelyWhenBackingFileIsMissing() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "missing-backing.gguf")
        let storageDir = root.appendingPathComponent("ModelsStorage")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let model = try await storage.importModel(from: source, name: "Disappearing File Model")
        try await storage.setActiveModel(id: model.id)

        let currentActiveID = try await storage.activeModelID()
        #expect(currentActiveID == model.id)

        let fileURL = try await storage.modelFileURL(for: model.id)
        #expect(fileURL != nil)

        // Remove file out-of-band behind storage's back
        try FileManager.default.removeItem(at: fileURL!)

        // activeModelDescriptor() must detect missing file, clear activeModelID, and return nil
        let activeDesc = try await storage.activeModelDescriptor()
        #expect(activeDesc == nil)

        let activeID = try await storage.activeModelID()
        #expect(activeID == nil)
    }
}


@Suite("M8.2 Active Local Model Binding Tests")
struct M82ActiveModelBindingTests {

    private func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M82BindingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createValidGGUFFile(at directory: URL, filename: String = "valid-model.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        var data = Data()

        // 1. Magic bytes 0x46554747 ("GGUF" in LE)
        let magic: UInt32 = 0x46554747
        var magicLE = magic.littleEndian
        data.append(Data(bytes: &magicLE, count: 4))

        // 2. Version UInt32 = 3
        let version: UInt32 = 3
        var versionLE = version.littleEndian
        data.append(Data(bytes: &versionLE, count: 4))

        // 3. Tensor count UInt64 = 10
        let tensorCount: UInt64 = 10
        var tensorCountLE = tensorCount.littleEndian
        data.append(Data(bytes: &tensorCountLE, count: 8))

        // 4. Metadata count UInt64 = 0
        let metadataCount: UInt64 = 0
        var metadataCountLE = metadataCount.littleEndian
        data.append(Data(bytes: &metadataCountLE, count: 8))

        data.append(Data(repeating: 0x00, count: 1024))
        try data.write(to: fileURL)
        return fileURL
    }

    @Test func testActiveModelBindingGuaranteesIdentityMatch() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "identity-test.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: storage
        )

        let descriptor = try await storage.importModel(from: source, name: "Identity Test Model")
        try await storage.setActiveModel(id: descriptor.id)

        let resolvedEngine = try await compositionRoot.activeLocalModelEngine()
        let engine = try #require(resolvedEngine)

        #expect(engine.identity.id == descriptor.id)
        #expect(engine.identity.name == descriptor.name)
        #expect(engine.identity.localURL != nil)
    }

    @Test func testNoActiveModelReturnsNilNoRuntimeCreated() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: storage
        )

        try await storage.setActiveModel(id: nil)

        let resolvedEngine = try await compositionRoot.activeLocalModelEngine()
        #expect(resolvedEngine == nil)
    }

    @Test func testLazyRuntimeInitialization() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "lazy-test.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: storage
        )

        let descriptor = try await storage.importModel(from: source, name: "Lazy Model")
        try await storage.setActiveModel(id: descriptor.id)

        let resolvedEngine = try await compositionRoot.activeLocalModelEngine()
        let engine = try #require(resolvedEngine)

        let state = await engine.lifecycleState
        #expect(state == .unloaded)
    }

    private struct StaleModelStorageMock: LocalModelStorage {
        let staleID: ModelID
        let returnDescriptor: Bool
        let fileURL: URL?

        func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor {
            fatalError("Not implemented")
        }
        func listModels() async throws -> [LocalModelDescriptor] { [] }
        func getModel(id: ModelID) async throws -> LocalModelDescriptor? { nil }
        func deleteModel(id: ModelID) async throws {}
        func setActiveModel(id: ModelID?) async throws {}
        func activeModelID() async throws -> ModelID? { staleID }
        func activeModelDescriptor() async throws -> LocalModelDescriptor? {
            guard returnDescriptor else { return nil }
            return LocalModelDescriptor(
                id: staleID,
                name: "Stale Model",
                filename: "stale.gguf",
                fileSizeBytes: 1024
            )
        }
        func modelFileURL(for id: ModelID) async throws -> URL? { fileURL }
    }

    @Test func testMissingOrStaleOrInvalidModelFailsClosed() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let rootDir = root.appendingPathComponent("M8Product")

        // Case A: activeModelID is set, but activeModelDescriptor returns nil (stale/missing descriptor)
        let staleID = ModelID(rawValue: "stale-missing-descriptor")
        let mockA = StaleModelStorageMock(staleID: staleID, returnDescriptor: false, fileURL: nil)
        let compositionRootA = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: mockA
        )

        do {
            _ = try await compositionRootA.activeLocalModelEngine()
            #expect(Bool(false), "Expected activeLocalModelEngine to fail closed when active descriptor is missing")
        } catch let err as LocalModelStorageError {
            #expect(err == .modelNotFound(staleID))
        }

        // Case B: activeModelDescriptor exists, but model file is missing on disk
        let missingFileURL = root.appendingPathComponent("nonexistent.gguf")
        let mockB = StaleModelStorageMock(staleID: staleID, returnDescriptor: true, fileURL: missingFileURL)
        let compositionRootB = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: mockB
        )

        do {
            _ = try await compositionRootB.activeLocalModelEngine()
            #expect(Bool(false), "Expected activeLocalModelEngine to fail closed when model file is missing on disk")
        } catch let err as LocalModelStorageError {
            #expect(err == .fileNotFound(missingFileURL))
        }
    }

    @Test func testNativeLoadFailurePropagatesWithoutFakeFallback() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Create a GGUF file with valid header but dummy payload (no tensors)
        let source = try createValidGGUFFile(at: root, filename: "no-tensors.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: storage
        )

        let descriptor = try await storage.importModel(from: source, name: "No Tensors Model")
        try await storage.setActiveModel(id: descriptor.id)

        let resolvedEngine = try await compositionRoot.activeLocalModelEngine()
        let engine = try #require(resolvedEngine)

        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Native model load must fail closed when tensor weights are missing")
        } catch {
            let state = await engine.lifecycleState
            if case .failed = state {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected state to be .failed")
            }
        }
    }


    private struct IdentityMismatchModelStorageMock: LocalModelStorage {
        let activeID: ModelID
        let mismatchedDescriptorID: ModelID
        let validFileURL: URL

        func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor {
            fatalError("Not implemented")
        }
        func listModels() async throws -> [LocalModelDescriptor] { [] }
        func getModel(id: ModelID) async throws -> LocalModelDescriptor? { nil }
        func deleteModel(id: ModelID) async throws {}
        func setActiveModel(id: ModelID?) async throws {}
        func activeModelID() async throws -> ModelID? { activeID }
        func activeModelDescriptor() async throws -> LocalModelDescriptor? {
            LocalModelDescriptor(
                id: mismatchedDescriptorID,
                name: "Mismatched Model",
                filename: "mismatched.gguf",
                fileSizeBytes: 1024
            )
        }
        func modelFileURL(for id: ModelID) async throws -> URL? { validFileURL }
    }

    @Test func testIdentityMismatchFailsClosed() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let validFile = try createValidGGUFFile(at: root, filename: "mismatched.gguf")
        let rootDir = root.appendingPathComponent("M8Product")

        let activeID = ModelID(rawValue: "active-model-A")
        let mismatchedDescriptorID = ModelID(rawValue: "descriptor-model-B")

        let mock = IdentityMismatchModelStorageMock(
            activeID: activeID,
            mismatchedDescriptorID: mismatchedDescriptorID,
            validFileURL: validFile
        )

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: mock
        )

        do {
            _ = try await compositionRoot.activeLocalModelEngine()
            #expect(Bool(false), "Expected activeLocalModelEngine to fail closed on identity mismatch")
        } catch let err as LocalModelStorageError {
            #expect(err == .modelNotFound(activeID))
        }
    }

    @Test func testDeterministicRuntimeCleanup() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "cleanup-test.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: storage
        )

        let descriptor = try await storage.importModel(from: source, name: "Cleanup Model")
        try await storage.setActiveModel(id: descriptor.id)

        let resolvedEngine = try await compositionRoot.activeLocalModelEngine()
        let engine = try #require(resolvedEngine)

        try await engine.unload()
        let state = await engine.lifecycleState
        #expect(state == .unloaded)
    }


    @Test func testSwitchActiveModelAtomicRollbackOnStorageFailure() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let fileB = try createValidGGUFFile(at: root, filename: "modelB.gguf")

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let innerStorage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descA = try await innerStorage.importModel(from: fileA, name: "Model A")
        let descB = try await innerStorage.importModel(from: fileB, name: "Model B")

        let modelA = descA.id
        let modelB = descB.id

        try await innerStorage.setActiveModel(id: modelA)

        let failingStorage = FailingSetActiveModelStorageMock(inner: innerStorage, failingTargetID: modelB)

        let rootDir = root.appendingPathComponent("M8Product")
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: rootDir,
            localModelStorage: failingStorage
        )

        // 1. Model A is active
        #expect(try await compositionRoot.localModelStorage.activeModelID() == modelA)

        // 2. Engine A is resolved and available
        let engineA = try #require(try await compositionRoot.activeLocalModelEngine())
        #expect(engineA.identity.id == modelA)

        // 3. Request switch to B -> A unloads -> storage.setActiveModel(B) throws failure
        do {
            try await compositionRoot.switchActiveModel(to: modelB)
            #expect(Bool(false), "Expected switchActiveModel to throw on storage failure for B")
        } catch let err as LocalModelStorageError {
            if case .storageCorrupt = err {
                // Expected simulated failure
            } else {
                #expect(Bool(false), "Unexpected error type: \(err)")
            }
        }

        // 4. Prove system invariants after failure:
        // - Active model remains A
        let activeAfterFailure = try await compositionRoot.localModelStorage.activeModelID()
        #expect(activeAfterFailure == modelA)

        // - B is not active
        #expect(activeAfterFailure != modelB)

        // - Runtime cache/engine resolution returns engine for A
        let engineAAfterFailure = try #require(try await compositionRoot.activeLocalModelEngine())
        #expect(engineAAfterFailure.identity.id == modelA)

        // - Model A engine can still be retrieved and used
        let stateAAfter = await engineAAfterFailure.lifecycleState
        #expect(stateAAfter == .unloaded)
    }
}


private actor FailingSetActiveModelStorageMock: LocalModelStorage {
    let inner: FileBackedLocalModelStorage
    let failingTargetID: ModelID

    init(inner: FileBackedLocalModelStorage, failingTargetID: ModelID) {
        self.inner = inner
        self.failingTargetID = failingTargetID
    }

    func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor {
        try await inner.importModel(from: sourceURL, name: name)
    }

    func listModels() async throws -> [LocalModelDescriptor] {
        try await inner.listModels()
    }

    func getModel(id: ModelID) async throws -> LocalModelDescriptor? {
        try await inner.getModel(id: id)
    }

    func deleteModel(id: ModelID) async throws {
        try await inner.deleteModel(id: id)
    }

    func setActiveModel(id: ModelID?) async throws {
        if id == failingTargetID {
            throw LocalModelStorageError.storageCorrupt("Simulated storage write failure for model B")
        }
        try await inner.setActiveModel(id: id)
    }

    func activeModelID() async throws -> ModelID? {
        try await inner.activeModelID()
    }

    func activeModelDescriptor() async throws -> LocalModelDescriptor? {
        try await inner.activeModelDescriptor()
    }

    func modelFileURL(for id: ModelID) async throws -> URL? {
        try await inner.modelFileURL(for: id)
    }
}
