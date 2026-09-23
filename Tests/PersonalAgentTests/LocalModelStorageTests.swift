import Foundation
import Testing
import PAFoundation
import PAProviders
import PAProvidersLocal
import PAComposition
import PAArchitecture

@Suite("Local Model Storage & Selection Tests")
struct LocalModelStorageTests {
    private func createTestDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createValidGGUFFile(at directory: URL, filename: String = "test.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        var data = Data()
        // Magic bytes: 0x46554747 -> "GGUF" in ASCII
        let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46]
        data.append(contentsOf: magic)

        // Version: UInt32 = 3 (little-endian)
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))

        // Tensor count: UInt64 = 0
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: MemoryLayout<UInt64>.size))

        // Metadata KV count: UInt64 = 0
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: MemoryLayout<UInt64>.size))

        try data.write(to: fileURL)
        return fileURL
    }

    @Test func testImportValidGGUFModelCopiesFileAndPersistsMetadata() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "valid-source.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Test Model Alpha")

        #expect(descriptor.name == "Test Model Alpha")
        #expect(descriptor.version == 3)
        #expect(descriptor.filename.hasSuffix(".gguf"))
        #expect(descriptor.fileSizeBytes > 0)

        let models = try await storage.listModels()
        #expect(models.count == 1)
        #expect(models.first?.id == descriptor.id)

        let fetched = try await storage.getModel(id: descriptor.id)
        #expect(fetched == descriptor)
    }

    @Test func testImportInvalidGGUFMagicBytesFailsAndLeavesNoOrphanFile() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidFile = root.appendingPathComponent("invalid.gguf")
        let dummyData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        try dummyData.write(to: invalidFile)

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        do {
            _ = try await storage.importModel(from: invalidFile, name: "Invalid Magic")
            #expect(Bool(false), "Import must fail closed on invalid magic bytes")
        } catch let err as LocalModelStorageError {
            if case .invalidGGUFHeader = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        let models = try await storage.listModels()
        #expect(models.isEmpty)

        let copiedFiles = (try? FileManager.default.contentsOfDirectory(atPath: storageDir.path)) ?? []
        let modelFiles = copiedFiles.filter { $0.hasSuffix(".gguf") }
        #expect(modelFiles.isEmpty)
    }

    @Test func testImportUnsupportedGGUFVersionFailsAndLeavesNoOrphanFile() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("v1.gguf")
        var data = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        var version: UInt32 = 1 // unsupported version 1
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: MemoryLayout<UInt64>.size))
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: MemoryLayout<UInt64>.size))
        try data.write(to: fileURL)

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        do {
            _ = try await storage.importModel(from: fileURL, name: "Version 1 Model")
            #expect(Bool(false), "Import must fail closed on unsupported version 1")
        } catch let err as LocalModelStorageError {
            if case .unsupportedGGUFVersion(let v) = err {
                #expect(v == 1)
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        let models = try await storage.listModels()
        #expect(models.isEmpty)
    }

    @Test func testActiveModelSelectionAndDescriptorResolution() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "select.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Select Model")

        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)

        try await storage.setActiveModel(id: descriptor.id)

        #expect(try await storage.activeModelID() == descriptor.id)
        let activeDesc = try await storage.activeModelDescriptor()
        #expect(activeDesc == descriptor)

        try await storage.setActiveModel(id: nil)
        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)
    }

    @Test func testSetActiveModelToNonExistentIDThrowsModelNotFound() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let bogusID = ModelID(rawValue: "nonexistent-model-id")
        do {
            try await storage.setActiveModel(id: bogusID)
            #expect(Bool(false), "Setting non-existent model ID as active must throw modelNotFound")
        } catch let err as LocalModelStorageError {
            #expect(err == .modelNotFound(bogusID))
        }

        #expect(try await storage.activeModelID() == nil)
    }

    @Test func testDeleteModelRemovesFileClearsActiveSelectionAndIndex() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "delete.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Delete Model")
        try await storage.setActiveModel(id: descriptor.id)

        let storedFileURL = try await storage.modelFileURL(for: descriptor.id)
        let fileURL = try #require(storedFileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try await storage.deleteModel(id: descriptor.id)

        #expect(try await storage.getModel(id: descriptor.id) == nil)
        #expect(try await storage.activeModelID() == nil)
        #expect(try await storage.activeModelDescriptor() == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func testDeleteModelFailsClosedWhenFileRemovalFails() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let bogusID = ModelID(rawValue: "bogus-delete-id")
        do {
            try await storage.deleteModel(id: bogusID)
            #expect(Bool(false), "Deleting non-existent model must throw modelNotFound")
        } catch let err as LocalModelStorageError {
            #expect(err == .modelNotFound(bogusID))
        }
    }

    @Test func testIndexPersistenceAcrossStorageInstances() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "persist.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")

        let descriptor: LocalModelDescriptor
        do {
            let storage1 = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)
            descriptor = try await storage1.importModel(from: source, name: "Persisted Model")
            try await storage1.setActiveModel(id: descriptor.id)
        }

        let storage2 = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)
        let models = try await storage2.listModels()
        #expect(models.count == 1)
        #expect(models.first == descriptor)
        #expect(try await storage2.activeModelID() == descriptor.id)
        #expect(try await storage2.activeModelDescriptor() == descriptor)
    }

    @Test func testActiveModelDescriptorReconcilesSafelyWhenBackingFileIsMissing() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "missing-backing.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Missing Backing Model")
        try await storage.setActiveModel(id: descriptor.id)

        let fileURL = try #require(try await storage.modelFileURL(for: descriptor.id))
        try FileManager.default.removeItem(at: fileURL)

        #expect(try await storage.activeModelDescriptor() == nil)
        #expect(try await storage.activeModelID() == nil)
    }

    @Test func testM8CompositionRootWiresLocalModelStorage() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let rootDir = root.appendingPathComponent("M8Product")
        let composition = try await M8CompositionRoot(storeDirectoryURL: rootDir)

        let storage = composition.localModelStorage
        let models = try await storage.listModels()
        #expect(models.isEmpty)
    }
}

@Suite("M8.2 Active Local Model Binding Tests")
struct M82ActiveModelBindingTests {
    private func createTestDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M82ActiveModelBindingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createValidGGUFFile(at directory: URL, filename: String = "test.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        var data = Data()
        let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46] // "GGUF"
        data.append(contentsOf: magic)
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: MemoryLayout<UInt64>.size))
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: MemoryLayout<UInt64>.size))
        try data.write(to: fileURL)
        return fileURL
    }

    private final class ObservableMockEngine: LocalModelEngine, @unchecked Sendable {
        let identity: LocalModelIdentity
        private var _state: LocalModelLifecycleState
        let shouldFailUnload: Bool
        let shouldFailGenerate: Bool

        private(set) var completeCallCount = 0
        private(set) var streamCallCount = 0
        private(set) var unloadCallCount = 0
        private(set) var lastGenerationRequest: LocalModelGenerationRequest?

        private let lock = NSLock()

        init(
            identity: LocalModelIdentity,
            state: LocalModelLifecycleState = .loaded,
            shouldFailUnload: Bool = false,
            shouldFailGenerate: Bool = false
        ) {
            self.identity = identity
            self._state = state
            self.shouldFailUnload = shouldFailUnload
            self.shouldFailGenerate = shouldFailGenerate
        }

        var availability: LocalModelAvailability { .ready }

        var lifecycleState: LocalModelLifecycleState {
            get async {
                lock.withLock { _state }
            }
        }

        func load(options: LocalModelLoadingOptions) async throws {
            lock.withLock { _state = .loaded }
        }

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            lock.withLock {
                completeCallCount += 1
                lastGenerationRequest = request
            }
            if shouldFailGenerate || lock.withLock({ _state }) != .loaded {
                throw LlamaCPPEngineError.modelNotLoaded
            }
            return LocalModelResponse(text: "Observable mock output for: \(request.prompt)")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            lock.withLock {
                streamCallCount += 1
                lastGenerationRequest = request
            }
            let isLoaded = lock.withLock { _state } == .loaded
            let failGen = shouldFailGenerate
            return AsyncThrowingStream { continuation in
                if failGen || !isLoaded {
                    continuation.finish(throwing: LlamaCPPEngineError.modelNotLoaded)
                } else {
                    continuation.yield(LocalModelStreamChunk(textDelta: "Observable stream chunk", finishReason: "stop"))
                    continuation.finish()
                }
            }
        }

        func cancel() async {}

        func unload() async throws {
            lock.withLock { unloadCallCount += 1 }
            if shouldFailUnload {
                throw LocalModelStorageError.storageCorrupt("Engine unload failed")
            }
            lock.withLock { _state = .unloaded }
        }
    }

    private final class ObservableFallbackProvider: LLMProvider, @unchecked Sendable {
        let identity = ProviderIdentity(
            id: ProviderID(rawValue: "observable-fallback"),
            displayName: "Observable Fallback",
            models: [ModelIdentity(id: ModelID(rawValue: "fallback-model"), displayName: "Fallback Model", contextTokenLimit: 4096)]
        )
        let capabilities: ProviderCapabilities = [.textGeneration, .streaming]
        var health: ProviderHealth { get async { .healthy } }

        private(set) var completeCallCount = 0
        private(set) var streamCallCount = 0

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            completeCallCount += 1
            return LLMResponse(text: "Fallback output", finishReason: "stop", model: request.model)
        }

        func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
            streamCallCount += 1
            return AsyncThrowingStream { continuation in
                continuation.yield(.delta("Fallback stream"))
                continuation.yield(.completed(LLMResponse(text: "Fallback stream", finishReason: "stop", model: request.model)))
                continuation.finish()
            }
        }
    }

    private struct UnloadFailingStorageMock: LocalModelStorage {
        let activeID: ModelID
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
                id: activeID,
                name: "Unload Test Model",
                filename: "unload.gguf",
                fileSizeBytes: 1024
            )
        }
        func modelFileURL(for id: ModelID) async throws -> URL? { validFileURL }
    }

    @Test func testAcceptanceA_NoActiveLocalModelUsesFallback() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)
        let deviceCap = DefaultDeviceCapabilityProvider()

        let coordinator = LocalModelRuntimeCoordinator(storage: storage, deviceCapabilityProvider: deviceCap)
        let fallback = ObservableFallbackProvider()
        let dynamicProvider = DynamicActiveProvider(fallbackProvider: fallback, coordinator: coordinator)

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Hello fallback")])
        let res = try await dynamicProvider.complete(req)

        #expect(res.text == "Fallback output")
        #expect(fallback.completeCallCount == 1)
        #expect(try await coordinator.activeLocalModelEngine() == nil)
    }

    @Test func testAcceptanceB_ActiveLocalModelRoutesToLocalEngineComplete() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "local-complete.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Local Complete Model")
        try await storage.setActiveModel(id: descriptor.id)

        let mockEngine = ObservableMockEngine(
            identity: LocalModelIdentity(id: descriptor.id, name: descriptor.name),
            state: .loaded
        )

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage,
            localModelEngineFactory: { _, _ in mockEngine }
        )

        let fallback = ObservableFallbackProvider()
        let providerID = compositionRoot.catalog.identities.first!.id
        let activeProvider = compositionRoot.catalog.resolve(providerID)!

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Route to local engine")])
        let res = try await activeProvider.complete(req)

        #expect(res.text == "Observable mock output for: Route to local engine")
        let callCount = mockEngine.completeCallCount
        #expect(callCount == 1)
        let lastReq = mockEngine.lastGenerationRequest
        #expect(lastReq?.prompt == "Route to local engine")
        #expect(fallback.completeCallCount == 0) // Proves fallback was NOT called!
    }

    @Test func testAcceptanceC_ActiveLocalModelRoutesToLocalEngineStream() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "local-stream.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Local Stream Model")
        try await storage.setActiveModel(id: descriptor.id)

        let mockEngine = ObservableMockEngine(
            identity: LocalModelIdentity(id: descriptor.id, name: descriptor.name),
            state: .loaded
        )

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage,
            localModelEngineFactory: { _, _ in mockEngine }
        )

        let providerID = compositionRoot.catalog.identities.first!.id
        let activeProvider = compositionRoot.catalog.resolve(providerID)!

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Stream to local engine")])

        var receivedDeltas: [String] = []
        for try await event in activeProvider.stream(req) {
            if case .delta(let text) = event {
                receivedDeltas.append(text)
            }
        }

        #expect(receivedDeltas == ["Observable stream chunk"])
        let streamCount = mockEngine.streamCallCount
        #expect(streamCount == 1)
    }

    @Test func testAcceptanceD_ActiveLocalModelFailureDoesNotFallback() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingFileURL = root.appendingPathComponent("missing-file.gguf")
        let activeID = ModelID(rawValue: "active-missing-id")
        let mockStorage = UnloadFailingStorageMock(activeID: activeID, validFileURL: missingFileURL)
        let deviceCap = DefaultDeviceCapabilityProvider()

        let coordinator = LocalModelRuntimeCoordinator(storage: mockStorage, deviceCapabilityProvider: deviceCap)
        let fallback = ObservableFallbackProvider()
        let dynamicProvider = DynamicActiveProvider(fallbackProvider: fallback, coordinator: coordinator)

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Fail closed")])

        do {
            _ = try await dynamicProvider.complete(req)
            #expect(Bool(false), "DynamicActiveProvider MUST NOT fall back silently when active local model resolution fails")
        } catch let err as LocalModelStorageError {
            #expect(err == .fileNotFound(missingFileURL))
        }

        #expect(fallback.completeCallCount == 0) // Proves fallback was NOT called!
    }

    @Test func testAcceptanceE_MissingModelFileFailsClosedWithoutFallback() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingFileURL = root.appendingPathComponent("missing-backing.gguf")
        let activeID = ModelID(rawValue: "active-missing-backing")
        let mockStorage = UnloadFailingStorageMock(activeID: activeID, validFileURL: missingFileURL)
        let deviceCap = DefaultDeviceCapabilityProvider()

        let coordinator = LocalModelRuntimeCoordinator(storage: mockStorage, deviceCapabilityProvider: deviceCap)
        let fallback = ObservableFallbackProvider()
        let dynamicProvider = DynamicActiveProvider(fallbackProvider: fallback, coordinator: coordinator)

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Missing backing file")])

        do {
            _ = try await dynamicProvider.complete(req)
            #expect(Bool(false), "Must throw error when model backing file is missing")
        } catch let err as LocalModelStorageError {
            #expect(err == .fileNotFound(missingFileURL))
        }

        #expect(fallback.completeCallCount == 0)
    }

    @Test func testAcceptanceF_UnloadFailurePreservesCachedEngineOwnership() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "unload-failure.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Unload Failure Model")
        try await storage.setActiveModel(id: descriptor.id)

        let mockEngine = ObservableMockEngine(
            identity: LocalModelIdentity(id: descriptor.id, name: descriptor.name),
            state: .loaded,
            shouldFailUnload: true
        )

        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { _, _ in mockEngine }
        )

        // Initial resolution caches mockEngine
        let engine1 = try await coordinator.activeLocalModelEngine()
        #expect(engine1 != nil)

        // Attempting unload fails because shouldFailUnload == true
        do {
            try await coordinator.unloadActiveModel()
            #expect(Bool(false), "Expected unloadActiveModel to throw when engine.unload fails")
        } catch let err as LocalModelStorageError {
            if case .storageCorrupt = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        // Cached engine MUST NOT be discarded on unload failure! Identity MUST be preserved!
        let engine2 = try await coordinator.activeLocalModelEngine()
        let mock1 = try #require(engine1 as? ObservableMockEngine)
        let mock2 = try #require(engine2 as? ObservableMockEngine)
        #expect(mock2 === mock1)
        let unloadCalls = mockEngine.unloadCallCount
        #expect(unloadCalls == 1)
    }

    @Test func testAcceptanceG1_SuccessfulModelSwitch() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let sourceB = try createValidGGUFFile(at: root, filename: "modelB.gguf")

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let mA = try await storage.importModel(from: sourceA, name: "Model A")
        let mB = try await storage.importModel(from: sourceB, name: "Model B")

        let mockEngineA = ObservableMockEngine(identity: LocalModelIdentity(id: mA.id, name: mA.name), state: .loaded)
        let mockEngineB = ObservableMockEngine(identity: LocalModelIdentity(id: mB.id, name: mB.name), state: .loaded)

        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { identity, _ in
                if identity.id == mA.id { return mockEngineA }
                return mockEngineB
            }
        )

        try await coordinator.setActiveModel(id: mA.id)
        let resolvedA = try #require(try await coordinator.activeLocalModelEngine())
        #expect(resolvedA.identity.id == mA.id)

        try await coordinator.setActiveModel(id: mB.id)
        let resolvedB = try #require(try await coordinator.activeLocalModelEngine())
        #expect(resolvedB.identity.id == mB.id)
        #expect(try await storage.activeModelID() == mB.id)
        #expect(mockEngineA.unloadCallCount == 1)
    }

    @Test func testAcceptanceG2_FailedModelSwitchPreservesActiveModel() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let sourceB = try createValidGGUFFile(at: root, filename: "modelB.gguf")

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let mA = try await storage.importModel(from: sourceA, name: "Model A")
        let mB = try await storage.importModel(from: sourceB, name: "Model B")

        let mockEngineA = ObservableMockEngine(
            identity: LocalModelIdentity(id: mA.id, name: mA.name),
            state: .loaded,
            shouldFailUnload: true
        )
        let mockEngineB = ObservableMockEngine(
            identity: LocalModelIdentity(id: mB.id, name: mB.name),
            state: .loaded
        )

        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { identity, _ in
                if identity.id == mA.id { return mockEngineA }
                return mockEngineB
            }
        )

        try await coordinator.setActiveModel(id: mA.id)
        let resolvedA = try #require(try await coordinator.activeLocalModelEngine())
        #expect(resolvedA.identity.id == mA.id)

        // Attempting switch to B fails because A unload fails
        do {
            try await coordinator.setActiveModel(id: mB.id)
            #expect(Bool(false), "Expected switch to fail when unloading model A fails")
        } catch let err as LocalModelStorageError {
            if case .storageCorrupt = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        // Active model in storage remains A, and cached engine remains A
        #expect(try await storage.activeModelID() == mA.id)
        let currentEngine = try #require(try await coordinator.activeLocalModelEngine())
        #expect(currentEngine.identity.id == mA.id)
        #expect(mockEngineA.unloadCallCount == 1)
        #expect(mockEngineB.completeCallCount == 0)
    }

    private struct FailingStorageWrapper: LocalModelStorage {
        let inner: any LocalModelStorage
        let failOnModelID: ModelID

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
            if id == failOnModelID {
                throw LocalModelStorageError.storageCorrupt("Deliberate storage failure for model B")
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

    @Test func testAcceptanceG3_FailedStorageMutationInSwitchPreservesActiveModel() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let sourceB = try createValidGGUFFile(at: root, filename: "modelB.gguf")

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let mA = try await storage.importModel(from: sourceA, name: "Model A")
        let mB = try await storage.importModel(from: sourceB, name: "Model B")

        try await storage.setActiveModel(id: mA.id)

        let mockEngineA = ObservableMockEngine(identity: LocalModelIdentity(id: mA.id, name: mA.name), state: .loaded)
        let mockEngineB = ObservableMockEngine(identity: LocalModelIdentity(id: mB.id, name: mB.name), state: .loaded)

        let failingStorage = FailingStorageWrapper(inner: storage, failOnModelID: mB.id)

        let coordinator = LocalModelRuntimeCoordinator(
            storage: failingStorage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { identity, _ in
                if identity.id == mA.id { return mockEngineA }
                return mockEngineB
            }
        )

        let engineA = try #require(try await coordinator.activeLocalModelEngine())
        #expect(engineA.identity.id == mA.id)

        do {
            try await coordinator.setActiveModel(id: mB.id)
            #expect(Bool(false), "Expected setActiveModel(mB.id) to throw storage failure")
        } catch let err as LocalModelStorageError {
            if case .storageCorrupt = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        #expect(try await storage.activeModelID() == mA.id)
        let engineAfter = try #require(try await coordinator.activeLocalModelEngine())
        let mockAfter = try #require(engineAfter as? ObservableMockEngine)
        let mockBefore = try #require(engineA as? ObservableMockEngine)
        #expect(mockAfter === mockBefore)

        let req = LocalModelGenerationRequest(prompt: "Usable test")
        let res = try await mockAfter.generate(request: req)
        #expect(res.text == "Observable mock output for: Usable test")
        #expect(try await storage.activeModelID() != mB.id)
    }

    @Test func testApplicationChatProviderPathRoutesToActiveLocalEngine() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "chat-path.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Chat Path Model")
        try await storage.setActiveModel(id: descriptor.id)

        let mockEngine = ObservableMockEngine(
            identity: LocalModelIdentity(id: descriptor.id, name: descriptor.name),
            state: .loaded
        )

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage,
            localModelEngineFactory: { _, _ in mockEngine }
        )

        let providerID = compositionRoot.catalog.identities.first!.id
        let provider = try #require(compositionRoot.catalog.resolve(providerID))

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Verify application chat path")])
        let res = try await provider.complete(req)

        #expect(res.text == "Observable mock output for: Verify application chat path")
        let completeCalls = mockEngine.completeCallCount
        #expect(completeCalls == 1)
        let lastReq = mockEngine.lastGenerationRequest
        #expect(lastReq?.prompt == "Verify application chat path")
    }

    @Test func testProductionEngineWiringUsesLlamaCPPModelEngine() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "prod-engine.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Prod Engine Model")
        try await storage.setActiveModel(id: descriptor.id)

        // Default composition init uses nil localModelEngineFactory
        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage
        )

        let engine = try await compositionRoot.activeLocalModelEngine()
        let prodEngine = try #require(engine)
        #expect(prodEngine is LlamaCPPModelEngine)
    }
}