import Foundation
import Testing
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAProvidersLocal
import PAMemory
@testable import PAComposition
import PASecurity

@Suite("M8 Product Architecture Tests")
struct M8ArchitectureTests {
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

    @Test func chatSkillRouteExecutesAndVerifiesDefaultSkill() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M8ChatSkillE2E_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let root = try await M8CompositionRoot(storeDirectoryURL: tempDir)
        guard let result = try await root.runChatSkillIfMatched(
            goalStatement: "  normalize this text  ",
            agentID: "personal.default"
        ) else {
            Issue.record("The chat route should select the declared Text Normalize skill")
            return
        }

        #expect(result.skillID.rawValue == "text.normalize")
        #expect(result.verified)

        guard let data = result.outputJSON.data(using: .utf8),
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
