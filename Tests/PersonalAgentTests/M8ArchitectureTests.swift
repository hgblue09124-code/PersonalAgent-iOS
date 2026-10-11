import Foundation
import Testing
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAProvidersLocal
import PAMemory
import PAStorageModels
import PASkills
@testable import PAComposition
import PASecurity

@Suite("M8 Product Architecture Tests")
struct M8ArchitectureTests {
    private struct ExplicitAllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("explicit test grant") }
    }

    @Test func unconfiguredCompositionProviderFailsClosed() async {
        let provider = DefaultCompositionProvider()
        #expect(await provider.health == .unavailable)

        await #expect(throws: ProviderRuntimeError.unavailable) {
            _ = try await provider.complete(
                LLMRequest(model: ModelID(rawValue: "default-text"), prompt: "hello")
            )
        }

        do {
            for try await _ in provider.stream(
                LLMRequest(model: ModelID(rawValue: "default-text"), prompt: "hello")
            ) {}
            Issue.record("unconfigured provider must not emit a successful stream")
        } catch let error as ProviderRuntimeError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("unexpected error: \\(error)")
        }
    }


    struct MockLocalEngine: LocalModelEngine {
        let identity: LocalModelIdentity
        var availability: LocalModelAvailability { get async { .ready } }
        var lifecycleState: LocalModelLifecycleState { get async { .loaded } }

        init(id: String = "test-llama") {
            self.identity = LocalModelIdentity(
                id: ModelID(rawValue: id),
                name: "Test Llama 3B",
                parameterCount: "3B",
                quantization: "Q4_K_M",
                contextTokenLimit: 8192
            )
        }

        func load(options: LocalModelLoadingOptions) async throws {}

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            LocalModelResponse(text: "Local response to: \(request.prompt)", finishReason: "stop")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(LocalModelStreamChunk(textDelta: "Local "))
                continuation.yield(LocalModelStreamChunk(textDelta: "streamed "))
                continuation.yield(LocalModelStreamChunk(textDelta: "response", finishReason: "stop"))
                continuation.finish()
            }
        }

        func cancel() async {}
        func unload() async throws {}
    }



    private actor DelayedLoadingLocalModelEngine: LocalModelEngine {
        let identity: LocalModelIdentity
        private var state: LocalModelLifecycleState = .unloaded
        private var started = false
        private var continuation: CheckedContinuation<Void, Never>?

        init(identity: LocalModelIdentity) {
            self.identity = identity
        }

        var availability: LocalModelAvailability { get async { .ready } }
        var lifecycleState: LocalModelLifecycleState { get async { state } }

        func hasStartedLoading() -> Bool { started }

        func load(options: LocalModelLoadingOptions) async throws {
            started = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            state = .loaded
        }

        func releaseLoad() {
            continuation?.resume()
            continuation = nil
        }

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            LocalModelResponse(text: "delayed local response")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(LocalModelStreamChunk(textDelta: "delayed local response", finishReason: "stop"))
                continuation.finish()
            }
        }

        func cancel() async {}

        func unload() async throws {
            state = .unloaded
        }
    }

    private struct RegisteredProductionSkillExecutor: SkillExecutor {
        func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
            #"{"value":"production-registry"}"#
        }

        func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
            outputJSON == #"{"value":"production-registry"}"#
        }
    }

    @Test func testM8CompositionRootAndAppSession() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M8Test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = try await M8CompositionRoot(storeDirectoryURL: tempDir)
        #expect(root.milestone == .m8)

        let session = root.session
        let initialState = await session.currentState()
        #expect(initialState.lifecycle == .running)

        let goalsBefore = await session.activeGoals()
        #expect(goalsBefore.isEmpty)

        let goalID = try await session.submitInput("Build M8 Product Foundation")
        let goalsAfter = await session.activeGoals()
        #expect(goalsAfter.count == 1)
        #expect(goalsAfter.first?.id == goalID)
        #expect(goalsAfter.first?.statement == "Build M8 Product Foundation")

        let runtimeState = await root.runtime.currentState()
        let sessionState = await session.currentState()
        #expect(runtimeState == sessionState)
    }

    @Test func memoryPersistsAcrossCompositionRootRecreationAndFeedsContext() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8MemoryE2E_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectedMemory = "I prefer green tea in the morning"
        let firstRoot = try await M8CompositionRoot(storeDirectoryURL: tempDir)
        try await firstRoot.remember(expectedMemory, kind: "preference")

        let initialContext = try await firstRoot.memoryContext(for: "green tea")
        #expect(initialContext.contains(expectedMemory))

        let restartedRoot = try await M8CompositionRoot(storeDirectoryURL: tempDir)
        let restoredContext = try await restartedRoot.memoryContext(for: "green tea")
        #expect(restoredContext.contains(expectedMemory))

        let snapshot = try await restartedRoot.memorySnapshot(limit: 50)
        #expect(snapshot.contains { $0.kind == "preference" && $0.content == expectedMemory })
    }


    @Test func productionCompositionUsesInjectedSkillExecutorRegistry() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8SkillRegistryE2E_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let skillDirectory = tempDir.appendingPathComponent("Skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let markdown = """
        id: custom.production
        name: Production Registered Skill
        version: 1.0.0
        description: Verify production composition passes the injected executor registry.
        executor: custom.production
        ---
        ## Input
        input.v1

        ## Output
        output.v1

        ## Rule
        Return the registered executor output.
        """
        try markdown.write(
            to: skillDirectory.appendingPathComponent("custom.production.Skill.md"),
            atomically: true,
            encoding: .utf8
        )

        let registry = SkillExecutorRegistry()
        await registry.register(RegisteredProductionSkillExecutor(), for: "custom.production")
        let root = try await M8CompositionRoot(
            storeDirectoryURL: tempDir,
            policy: ExplicitAllowPolicy(),
            skillExecutors: registry
        )
        let output = try await root.skillRuntime.executeVerified(
            id: SkillID(rawValue: "custom.production"),
            inputJSON: #"{"value":"input"}"#,
            policy: ExplicitAllowPolicy()
        )
        #expect(output == #"{"value":"production-registry"}"#)
    }




    @Test func cancelledLocalModelLoadCallerRejectsLateEngineSuccess() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8LocalLoadCancel_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sourceURL = tempDir.appendingPathComponent("delayed.gguf")
        var data = Data([0x47, 0x47, 0x55, 0x46])
        var version: UInt32 = 3
        var tensorCount: UInt64 = 0
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))
        data.append(Data(bytes: &tensorCount, count: MemoryLayout<UInt64>.size))
        data.append(Data(bytes: &metadataCount, count: MemoryLayout<UInt64>.size))
        try data.write(to: sourceURL)

        let storage = try FileBackedLocalModelStorage(
            modelsDirectoryURL: tempDir.appendingPathComponent("Models", isDirectory: true)
        )
        let descriptor = try await storage.importModel(from: sourceURL, name: "Delayed model")
        try await storage.setActiveModel(id: descriptor.id)
        let fileURL = try #require(await storage.modelFileURL(for: descriptor.id))
        let identity = LocalModelIdentity(
            id: descriptor.id,
            name: descriptor.name,
            parameterCount: descriptor.parameterCount,
            quantization: descriptor.quantization,
            contextTokenLimit: descriptor.contextWindow ?? 8192,
            fileSizeBytes: descriptor.fileSizeBytes,
            localURL: fileURL
        )
        let engine = DelayedLoadingLocalModelEngine(identity: identity)
        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { _, _ in engine }
        )

        let task = Task { try await coordinator.loadActiveModel() }
        for _ in 0..<1_000 {
            if await engine.hasStartedLoading() { break }
            await Task.yield()
        }
        #expect(await engine.hasStartedLoading())
        task.cancel()
        await engine.releaseLoad()

        await #expect(throws: LlamaCPPEngineError.cancelled) {
            _ = try await task.value
        }
    }

    @Test func productionChatRoutesWorkspaceSearchSkillThroughModule() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8ChatWorkspaceSkill_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspaceURL = tempDir.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "needle content".write(
            to: workspaceURL.appendingPathComponent("needle.txt"),
            atomically: true,
            encoding: .utf8
        )

        let skillDirectory = tempDir.appendingPathComponent("Skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillMarkdown = """
        id: workspace.search.test
        name: Workspace Search
        version: 1.0.0
        description: Search workspace files for a text query.
        moduleID: tool.workspace.read
        chatInputAdapter: workspace.search
        ---
        ## Input
        tool.workspace.read.input

        ## Output
        tool.workspace.read.output

        ## Rule
        Search workspace text for the supplied query.
        """
        try skillMarkdown.write(
            to: skillDirectory.appendingPathComponent("workspace.search.test.Skill.md"),
            atomically: true,
            encoding: .utf8
        )

        let agentDirectory = tempDir.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        let agentMarkdown = """
        id: personal.default
        name: Workspace Search Agent
        version: 1.0.0
        description: Search workspace content.
        ---
        ## Skills
        workspace.search.test

        ## Rule
        Select only the declared workspace search Skill.
        """
        try agentMarkdown.write(
            to: agentDirectory.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )

        let root = try await M8CompositionRoot(
            storeDirectoryURL: tempDir,
            policy: ExplicitAllowPolicy(),
            workspaceToolsEnabled: true
        )
        let result = try await root.runChatSkillIfMatched(
            goalStatement: "Workspace Search: needle",
            agentID: "personal.default"
        )
        let verified = try #require(result)
        #expect(verified.skillID == SkillID(rawValue: "workspace.search.test"))
        #expect(verified.verified)

        let wrapper = try #require(
            try JSONSerialization.jsonObject(with: Data(verified.outputJSON.utf8)) as? [String: String]
        )
        let toolOutput = try #require(wrapper["output"])
        let output = try #require(
            try JSONSerialization.jsonObject(with: Data(toolOutput.utf8)) as? [String: Any]
        )
        let matches = try #require(output["matches"] as? [String])
        #expect(matches.contains("workspace/needle.txt"))
    }

    @Test func productionRootExecutesInstalledModuleBackedSkill() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8ModuleSkillE2E_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspaceURL = tempDir.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "needle content".write(
            to: workspaceURL.appendingPathComponent("needle.txt"),
            atomically: true,
            encoding: .utf8
        )

        let skillDirectory = tempDir.appendingPathComponent("Skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let markdown = """
        id: workspace.search.test
        name: Workspace Search Test
        version: 1.0.0
        description: Search workspace files through the authorized workspace read module.
        moduleID: tool.workspace.read
        ---
        ## Input
        tool.workspace.read.input

        ## Output
        tool.workspace.read.output

        ## Rule
        Search workspace text for the supplied query.
        """
        try markdown.write(
            to: skillDirectory.appendingPathComponent("workspace.search.test.Skill.md"),
            atomically: true,
            encoding: .utf8
        )

        let root = try await M8CompositionRoot(
            storeDirectoryURL: tempDir,
            policy: ExplicitAllowPolicy(),
            workspaceToolsEnabled: true
        )
        let toolArguments = try JSONSerialization.data(
            withJSONObject: ["operation": "search", "query": "needle"],
            options: [.sortedKeys]
        )
        let inputData = try JSONSerialization.data(
            withJSONObject: ["arguments": String(decoding: toolArguments, as: UTF8.self)],
            options: [.sortedKeys]
        )
        let outputJSON = try await root.executeSkill(
            id: SkillID(rawValue: "workspace.search.test"),
            inputJSON: String(decoding: inputData, as: UTF8.self)
        )

        let wrapper = try #require(
            try JSONSerialization.jsonObject(with: Data(outputJSON.utf8)) as? [String: String]
        )
        let toolOutput = try #require(wrapper["output"])
        let result = try #require(
            try JSONSerialization.jsonObject(with: Data(toolOutput.utf8)) as? [String: Any]
        )
        let matches = try #require(result["matches"] as? [String])
        #expect(matches.contains("workspace/needle.txt"))
    }

    @Test func chatSkillRouteExecutesAndVerifiesDefaultSkill() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8ChatSkillE2E_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = try await M8CompositionRoot(storeDirectoryURL: tempDir, policy: ExplicitAllowPolicy())
        guard let result = try await root.runChatSkillIfMatched(
            goalStatement: "  normalize this text  ",
            agentID: "personal.default"
        ) else {
            Issue.record("The chat route should select the declared Text Normalize skill")
            return
        }

        #expect(result.skillID.rawValue == "text.normalize")
        #expect(result.verified)

        guard let data = result.outputJSON.data(using: String.Encoding.utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            Issue.record("The verified Skill result must contain a JSON text field")
            return
        }
        #expect(object["text"] == "normalize this text")
    }

    @Test func testLocalModelProviderAdapter() async throws {
        let mockEngine = MockLocalEngine()
        let adapter = LocalModelProviderAdapter(engine: mockEngine)

        #expect(adapter.capabilities.contains(.localInference))
        #expect(adapter.capabilities.contains(.textGeneration))
        #expect(adapter.capabilities.contains(.streaming))

        let health = await adapter.health
        #expect(health == .healthy)

        let request = LLMRequest(model: ModelID(rawValue: "test-llama"), prompt: "Hello local LLM!")
        let response = try await adapter.complete(request)
        #expect(response.text == "Local response to: Hello local LLM!")

        var streamedText = ""
        for try await event in adapter.stream(request) {
            if case .delta(let delta) = event {
                streamedText += delta
            }
        }
        #expect(streamedText == "Local streamed response")
    }

    @Test func testDeviceCapabilityProvider() async throws {
        let initial = DeviceStateSnapshot(
            thermalState: .nominal,
            memoryPressure: .normal,
            networkStatus: .wifi,
            applicationState: .active,
            availableStorageBytes: 50_000_000_000
        )
        let provider = DefaultDeviceCapabilityProvider(initialSnapshot: initial)

        let snapshot = await provider.snapshot()
        #expect(snapshot.thermalState == .nominal)
        #expect(snapshot.memoryPressure == .normal)
        #expect(snapshot.networkStatus == .wifi)
        #expect(snapshot.applicationState == .active)
        #expect(snapshot.availableStorageBytes == 50_000_000_000)

        let thermal = await provider.thermalState
        #expect(thermal == .nominal)
    }

    @Test func testProductPersistenceContainerDomainIsolation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M8PersistenceTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try ProductPersistenceContainer(baseDirectoryURL: tempDir)
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: container.agentDurableDirectoryURL.path))
        #expect(fm.fileExists(atPath: container.sessionDataDirectoryURL.path))
        #expect(fm.fileExists(atPath: container.modelMetadataDirectoryURL.path))
        #expect(fm.fileExists(atPath: container.appPreferencesDirectoryURL.path))
        #expect(fm.fileExists(atPath: container.secretsDirectoryURL.path))

        #expect(container.agentDurableDirectoryURL.lastPathComponent == "AgentDurableState")
        #expect(container.sessionDataDirectoryURL.lastPathComponent == "SessionData")
        #expect(container.modelMetadataDirectoryURL.lastPathComponent == "ModelMetadata")
        #expect(container.appPreferencesDirectoryURL.lastPathComponent == "AppPreferences")
        #expect(container.secretsDirectoryURL.lastPathComponent == "Secrets")
    }
}
