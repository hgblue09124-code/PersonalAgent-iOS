with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

# Remove old trailing tests and replace with clean Acceptance Tests A-G
suite_end = content.rfind("private struct UnloadFailingStorageMock")
if suite_end != -1:
    base_content = content[:suite_end]
else:
    base_content = content

acceptance_tests = """
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

    private final class ObservableFallbackProvider: LLMProvider, @unchecked Sendable {
        let identity = ProviderIdentity(id: ProviderID(rawValue: "observable-fallback"), displayName: "Observable Fallback")
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

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage
        )

        let provider = compositionRoot.catalog.identities.first
        let activeProvider = try #require(compositionRoot.catalog.resolve(provider!.id))

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Route to local")])
        let res = try await activeProvider.complete(req)

        #expect(!res.text.isEmpty)
    }

    @Test func testAcceptanceC_ActiveLocalModelRoutesToLocalEngineStream() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try createValidGGUFFile(at: root, filename: "local-stream.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let descriptor = try await storage.importModel(from: source, name: "Local Stream Model")
        try await storage.setActiveModel(id: descriptor.id)

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage
        )

        let providerID = compositionRoot.catalog.identities.first!.id
        let provider = compositionRoot.catalog.resolve(providerID)!

        let req = LLMRequest(model: ModelID(rawValue: "test-model"), messages: [ProviderMessage(role: .user, content: "Stream to local")])

        var receivedEvents: [LLMStreamEvent] = []
        for try await event in provider.stream(req) {
            receivedEvents.append(event)
        }

        #expect(!receivedEvents.isEmpty)
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

        #expect(fallback.completeCallCount == 0) // Fallback provider MUST NOT be called!
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

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage
        )

        let descriptor = try await storage.importModel(from: source, name: "Unload Failure Model")
        try await compositionRoot.setActiveLocalModel(id: descriptor.id)

        let engine = try #require(try await compositionRoot.activeLocalModelEngine())
        #expect(engine.identity.id == descriptor.id)

        try await compositionRoot.unloadActiveLocalModel()
        let state = await engine.lifecycleState
        #expect(state == .unloaded)
    }

    @Test func testAcceptanceG_ModelSwitchingLifecycle() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let sourceB = try createValidGGUFFile(at: root, filename: "modelB.gguf")

        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let compositionRoot = try await M8CompositionRoot(
            storeDirectoryURL: root.appendingPathComponent("M8Product"),
            localModelStorage: storage
        )

        let mA = try await storage.importModel(from: sourceA, name: "Model A")
        let mB = try await storage.importModel(from: sourceB, name: "Model B")

        try await compositionRoot.setActiveLocalModel(id: mA.id)
        let eA = try #require(try await compositionRoot.activeLocalModelEngine())
        #expect(eA.identity.id == mA.id)

        try await compositionRoot.setActiveLocalModel(id: mB.id)
        let eB = try #require(try await compositionRoot.activeLocalModelEngine())
        #expect(eB.identity.id == mB.id)
        #expect(try await storage.activeModelID() == mB.id)
    }
}
"""

with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
    f.write(base_content + acceptance_tests)

print("Updated LocalModelStorageTests.swift with Acceptance Tests A-G")
