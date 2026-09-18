import Foundation
import Testing
import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAProvidersLocal
import PAMemory
import PAComposition
import PASecurity

@Suite("M8 Product Architecture Tests")
struct M8ArchitectureTests {

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

        // Confirm session state matches AgentRuntime state directly without duplication
        let runtimeState = await root.runtime.currentState()
        let sessionState = await session.currentState()
        #expect(runtimeState == sessionState)
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
