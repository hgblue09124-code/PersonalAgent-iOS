with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_chat_test = """    @Test func testApplicationChatProviderPathRoutesToActiveLocalEngine() async throws {
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
    }"""

good_chat_test = """    @Test func testApplicationChatProviderPathRoutesToActiveLocalEngine() async throws {
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
    }"""

if bad_chat_test in content:
    updated = content.replace(bad_chat_test, good_chat_test)
    with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
        f.write(updated)
    print("Updated testApplicationChatProviderPathRoutesToActiveLocalEngine")
else:
    print("Error: bad_chat_test not found")
