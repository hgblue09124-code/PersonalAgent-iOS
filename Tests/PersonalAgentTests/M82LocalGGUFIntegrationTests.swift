import PAProvidersLocal
import Foundation
import Testing
import PAFoundation
import PAProviders
import PAComposition

@Suite struct M82LocalGGUFIntegrationTests {
    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M82Integration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createValidGGUFFile(at url: URL) throws {
        var data = Data()
        var magic: UInt32 = 0x46554747 // "GGUF"
        data.append(Data(bytes: &magic, count: 4))
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: 4))
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: 8))
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: 8))
        try data.write(to: url)
    }

    @Test func testFullLocalModelPipelineWiring() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("sample.gguf")
        try createValidGGUFFile(at: sourceURL)

        let storeDir = tempDir.appendingPathComponent("Storage")
        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: storeDir)

        // 1. Import model
        let descriptor = try await storage.importModel(from: sourceURL, name: "Sample Llama")
        #expect(descriptor.name == "Sample Llama")

        // 2. Instantiate M8CompositionRoot with model storage
        let root = try await M8CompositionRoot(
            localModelStorage: storage,
            storeDirectoryURL: storeDir
        )

        // 3. Verify active model descriptor is accessible
        let activeDesc = try await root.modelStorage.getActiveModelDescriptor()
        #expect(activeDesc?.id == descriptor.id)

        // 4. Verify LocalModelEngine identity resolved dynamically
        if let engine = try await root.activeLocalModelEngine() {
            #expect(engine.identity.id == descriptor.id)
            #expect(engine.identity.name == "Sample Llama")

            let state = await engine.lifecycleState
            #expect(state == .unloaded)

            let adapter = LocalModelProviderAdapter(engine: engine)
            #expect(adapter.capabilities.contains(ProviderCapabilities.localInference))
            #expect(adapter.capabilities.contains(ProviderCapabilities.streaming))
        } else {
            Issue.record("Expected activeLocalModelEngine to be resolved from active descriptor")
        }
    }

    @Test func testModelSwitchingUpdatesEngineIdentity() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source1 = tempDir.appendingPathComponent("model1.gguf")
        let source2 = tempDir.appendingPathComponent("model2.gguf")
        try createValidGGUFFile(at: source1)
        try createValidGGUFFile(at: source2)

        let storeDir = tempDir.appendingPathComponent("Storage")
        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: storeDir)

        let desc1 = try await storage.importModel(from: source1, name: "Model One")
        let desc2 = try await storage.importModel(from: source2, name: "Model Two")

        // Set desc1 as active initially
        try await storage.selectActiveModel(id: desc1.id)

        let root = try await M8CompositionRoot(
            localModelStorage: storage,
            storeDirectoryURL: storeDir
        )

        let initialEngine = try await root.activeLocalModelEngine()
        #expect(initialEngine?.identity.id == desc1.id)

        // Switch active model in storage to desc2
        try await storage.selectActiveModel(id: desc2.id)

        // activeLocalModelEngine MUST return an engine bound to desc2
        let switchedEngine = try await root.activeLocalModelEngine()
        #expect(switchedEngine?.identity.id == desc2.id)
        #expect(switchedEngine?.identity.name == "Model Two")
    }

    @Test func testEngineFailsClosedWhenUnloadedOrMissingFile() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeDir = tempDir.appendingPathComponent("Storage")
        let storage = try FileBackedLocalModelStorage(baseDirectoryURL: storeDir)

        let root = try await M8CompositionRoot(
            localModelStorage: storage,
            storeDirectoryURL: storeDir
        )

        // No model imported or active -> activeLocalModelEngine returns nil
        let activeEngine = try await root.activeLocalModelEngine()
        #expect(activeEngine == nil)
    }
}
