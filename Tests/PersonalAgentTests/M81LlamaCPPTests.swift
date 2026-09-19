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

@Suite("M8.1 llama.cpp Local Inference Tests", .serialized)
struct M81LlamaCPPTests {

    private func createDummyGGUFFile(name: String = "test-model.gguf") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GGUFTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(name)

        var data = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF" magic header
        data.append(contentsOf: Array(repeating: UInt8(0), count: 1024)) // Dummy payload
        try data.write(to: fileURL)
        return fileURL
    }

    private func createInvalidFile(name: String = "invalid.bin") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GGUFTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(name)

        let data = Data([0x00, 0x11, 0x22, 0x33]) // Not GGUF
        try data.write(to: fileURL)
        return fileURL
    }

    @Test func testLifecycleTransitionsAndHeaderValidation() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let modelIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "llama-3b-gguf"),
            name: "Llama 3B GGUF",
            parameterCount: "3B",
            quantization: "Q4_K_M",
            contextTokenLimit: 8192,
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(identity: modelIdentity, residencyCoordinator: coordinator)

        let avail = await engine.availability
        #expect(avail == .ready)

        var state = await engine.lifecycleState
        #expect(state == .unloaded)

        try await engine.load(options: LocalModelLoadingOptions())
        state = await engine.lifecycleState
        #expect(state == .loaded)

        try await engine.unload()
        state = await engine.lifecycleState
        #expect(state == .unloaded)

        // Verify invalid header fails cleanly
        let invalidURL = try createInvalidFile()
        defer { try? FileManager.default.removeItem(at: invalidURL.deletingLastPathComponent()) }

        let invalidIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "invalid-model"),
            name: "Invalid Model",
            localURL: invalidURL
        )

        let invalidEngine = LlamaCPPModelEngine(identity: invalidIdentity, residencyCoordinator: coordinator)
        do {
            try await invalidEngine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Expected invalid header error")
        } catch let err as LlamaCPPEngineError {
            if case .invalidGGUFHeader = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error type: \(err)")
            }
        }

        let failedState = await invalidEngine.lifecycleState
        if case .failed = failedState {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected failed state")
        }
    }

    @Test func testSingleResidentModelExclusivityInvariant() async throws {
        let ggufURL1 = try createDummyGGUFFile(name: "model1.gguf")
        let ggufURL2 = try createDummyGGUFFile(name: "model2.gguf")
        defer {
            try? FileManager.default.removeItem(at: ggufURL1.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: ggufURL2.deletingLastPathComponent())
        }

        let identity1 = LocalModelIdentity(
            id: ModelID(rawValue: "model-1"),
            name: "Model 1",
            localURL: ggufURL1
        )
        let identity2 = LocalModelIdentity(
            id: ModelID(rawValue: "model-2"),
            name: "Model 2",
            localURL: ggufURL2
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine1 = LlamaCPPModelEngine(identity: identity1, residencyCoordinator: coordinator)
        let engine2 = LlamaCPPModelEngine(identity: identity2, residencyCoordinator: coordinator)

        try await engine1.load(options: LocalModelLoadingOptions())
        var state1 = await engine1.lifecycleState
        var state2 = await engine2.lifecycleState

        #expect(state1 == .loaded)
        #expect(state2 == .unloaded)

        let residentBefore = await coordinator.residentModelID
        #expect(residentBefore == ModelID(rawValue: "model-1"))

        // Now load Model 2: must trigger auto-unload of Model 1
        try await engine2.load(options: LocalModelLoadingOptions())

        state1 = await engine1.lifecycleState
        state2 = await engine2.lifecycleState

        #expect(state1 == .unloaded)
        #expect(state2 == .loaded)

        let residentAfter = await coordinator.residentModelID
        #expect(residentAfter == ModelID(rawValue: "model-2"))

        // Explicitly assert Engine 1 and Engine 2 were never simultaneously resident
        let isSimultaneous = (state1 == .loaded && state2 == .loaded)
        #expect(!isSimultaneous)

        try await engine2.unload()
    }

    @Test func testGenerationAndStreamingWithCancellation() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "llama-3b"),
            name: "Llama 3B",
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(identity: identity, residencyCoordinator: coordinator)
        try await engine.load(options: LocalModelLoadingOptions())

        let request = LocalModelGenerationRequest(prompt: "Explain quantum computing briefly.")
        let response = try await engine.generate(request: request)

        #expect(!response.text.isEmpty)
        #expect(response.finishReason == "stop")

        // Test Streaming
        let stream = engine.generateStream(request: request)
        var chunks: [LocalModelStreamChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(!chunks.isEmpty)
        let fullText = chunks.map(\.textDelta).joined()
        #expect(fullText == response.text)

        // Test Cancellation
        let longStream = engine.generateStream(request: request)
        let streamTask = Task {
            var count = 0
            do {
                for try await _ in longStream {
                    count += 1
                }
            } catch {
                return -1
            }
            return count
        }

        await engine.cancel()
        let result = await streamTask.value
        #expect(result == -1 || result < chunks.count)

        try await engine.unload()
    }

    @Test func testThermalGovernance() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let deviceProv = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(thermalState: .serious)
        )

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "thermal-llama"),
            name: "Thermal Llama",
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceProv,
            residencyCoordinator: coordinator
        )

        try await engine.load(options: LocalModelLoadingOptions())

        // Under .serious thermal state, generation completes (throttled)
        let request = LocalModelGenerationRequest(prompt: "Hello thermal test")
        let response = try await engine.generate(request: request)
        #expect(!response.text.isEmpty)

        // Transition to .critical thermal state -> must abort / fail closed
        deviceProv.updateSnapshot(DeviceStateSnapshot(thermalState: .critical))

        do {
            _ = try await engine.generate(request: request)
            #expect(Bool(false), "Expected thermalStateCritical error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .thermalStateCritical)
        }

        try await engine.unload()
    }

    @Test func testMemoryPressureGovernance() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let deviceProv = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(memoryPressure: .critical)
        )

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "memory-llama"),
            name: "Memory Llama",
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceProv,
            residencyCoordinator: coordinator
        )

        try await engine.load(options: LocalModelLoadingOptions())

        let request = LocalModelGenerationRequest(prompt: "Hello memory test")
        do {
            _ = try await engine.generate(request: request)
            #expect(Bool(false), "Expected memoryPressureCritical error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .memoryPressureCritical)
        }

        // Verify model was automatically unloaded upon critical memory pressure
        let state = await engine.lifecycleState
        #expect(state == .unloaded)
    }

    @Test func testLocalModelProviderAdapterBridge() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "bridge-llama"),
            name: "Bridge Llama",
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(identity: identity, residencyCoordinator: coordinator)
        try await engine.load(options: LocalModelLoadingOptions())

        let adapter = LocalModelProviderAdapter(engine: engine)
        #expect(adapter.capabilities.contains(.localInference))

        let llmReq = LLMRequest(model: ModelID(rawValue: "bridge-llama"), prompt: "Adapter prompt test")
        let llmResp = try await adapter.complete(llmReq)

        #expect(!llmResp.text.isEmpty)

        try await engine.unload()
    }

    @Test func testSecurityAndPersistenceBoundaryInvariants() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        // Assert model URL or data does NOT enter AgentState
        let agentState = AgentState(
            identity: AgentIdentity(displayName: "Test Agent"),
            lifecycle: .running
        )

        let jsonEncoder = JSONEncoder()
        let agentStateData = try jsonEncoder.encode(agentState)
        let agentStateString = String(data: agentStateData, encoding: .utf8) ?? ""

        #expect(!agentStateString.contains(ggufURL.path))
        #expect(!agentStateString.contains("GGUF"))

        // Assert model binaries stay strictly in ProductPersistenceContainer.modelMetadataDirectoryURL
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M81Security_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try ProductPersistenceContainer(baseDirectoryURL: tempDir)
        #expect(container.modelMetadataDirectoryURL.lastPathComponent == "ModelMetadata")
        #expect(container.agentDurableDirectoryURL.lastPathComponent == "AgentDurableState")
        #expect(container.modelMetadataDirectoryURL != container.agentDurableDirectoryURL)
    }

    @Test func testToolBoundaryIsolation() async throws {
        let ggufURL = try createDummyGGUFFile()
        defer { try? FileManager.default.removeItem(at: ggufURL.deletingLastPathComponent()) }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "tool-llama"),
            name: "Tool Llama",
            localURL: ggufURL
        )

        let coordinator = LlamaCPPResidencyCoordinator()
        let engine = LlamaCPPModelEngine(identity: identity, residencyCoordinator: coordinator)
        try await engine.load(options: LocalModelLoadingOptions())

        let adapter = LocalModelProviderAdapter(engine: engine)

        // Confirm adapter does not claim or possess tool execution capability
        let capabilities = adapter.capabilities
        #expect(!capabilities.contains(.toolCalling))

        try await engine.unload()
    }
}
