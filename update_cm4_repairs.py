with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

# Replace testAcceptanceF with identity comparison (e2 === e1)
old_f = """        // Cached engine MUST NOT be discarded on unload failure!
        let engine2 = try await coordinator.activeLocalModelEngine()
        #expect(engine2 != nil)
        let unloadCalls = mockEngine.unloadCallCount
        #expect(unloadCalls == 1)"""

new_f = """        // Cached engine MUST NOT be discarded on unload failure! Identity MUST be preserved!
        let engine2 = try await coordinator.activeLocalModelEngine()
        let e2 = try #require(engine2)
        let e1 = try #require(engine1)
        #expect(e2 === e1)
        let unloadCalls = mockEngine.unloadCallCount
        #expect(unloadCalls == 1)"""

content = content.replace(old_f, new_f)

# Add G3 (switch fails on storage persistence) and H (Application/Chat provider path) and I (Production engine wiring)
additional_tests = """
    @Test func testAcceptanceG3_FailedStorageMutationInSwitchPreservesActiveModel() async throws {
        let root = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceA = try createValidGGUFFile(at: root, filename: "modelA.gguf")
        let storageDir = root.appendingPathComponent("ModelMetadata").appendingPathComponent("Models")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: storageDir)

        let mA = try await storage.importModel(from: sourceA, name: "Model A")
        try await storage.setActiveModel(id: mA.id)

        let mockEngineA = ObservableMockEngine(identity: LocalModelIdentity(id: mA.id, name: mA.name), state: .loaded)

        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { _, _ in mockEngineA }
        )

        let activeBefore = try await storage.activeModelID()
        #expect(activeBefore == mA.id)

        // Attempting to set an invalid/bogus model ID fails storage validation
        let bogusID = ModelID(rawValue: "bogus-model-b")
        do {
            try await coordinator.setActiveModel(id: bogusID)
            #expect(Bool(false), "Expected setting bogus model ID to throw modelNotFound")
        } catch let err as LocalModelStorageError {
            #expect(err == .modelNotFound(bogusID))
        }

        // Active model in storage remains A
        #expect(try await storage.activeModelID() == mA.id)
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

        let state = await compositionRoot.session.currentState()
        #expect(state.lifecycle == .running)

        let submitResult = try await compositionRoot.session.submitInput("Verify application chat path")
        #expect(submitResult.rawValue != "")

        let completeCalls = mockEngine.completeCallCount
        #expect(completeCalls >= 1)
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
}"""

last_brace = content.rfind("}")
if last_brace != -1:
    updated_content = content[:last_brace] + additional_tests
    with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
        f.write(updated_content)
    print("Updated LocalModelStorageTests.swift with repairs G3, Chat path, and Prod engine wiring")
else:
    print("Error: closing brace not found")
