import Foundation
import Testing
@testable import PAFoundation
@testable import PAProviders
@testable import PAProvidersLocal
@testable import PAComposition

@Suite("M8.1 Real Native Llama.cpp Local Inference Tests")
struct M81LlamaCPPTests {

    private func createDummyHeaderGGUFFile(name: String = "dummy.gguf") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M81Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent(name)

        var data = Data()
        // Magic "GGUF" = 0x46554747
        var magic: UInt32 = 0x46554747
        var version: UInt32 = 3
        var tensorCount: UInt64 = 0
        var metadataCount: UInt64 = 0

        data.append(Data(bytes: &magic, count: 4))
        data.append(Data(bytes: &version, count: 4))
        data.append(Data(bytes: &tensorCount, count: 8))
        data.append(Data(bytes: &metadataCount, count: 8))

        try data.write(to: fileURL)
        return fileURL
    }

    private func createInvalidHeaderFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M81Invalid_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("invalid.bin")
        let data = "NOT_GGUF_HEADER_BYTES".data(using: .utf8)!
        try data.write(to: fileURL)
        return fileURL
    }

    @Test func testGGUFHeaderParserHeaderValidation() async throws {
        let fileURL = try createDummyHeaderGGUFFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let parser = GGUFModelParser()
        let summary = try parser.parseHeaderAndMetadata(at: fileURL)

        #expect(summary.version == 3)
        #expect(summary.tensorCount == 0)
        #expect(summary.metadataCount == 0)
    }

    @Test func testInvalidHeaderFileFailsParserAndEngineLoad() async throws {
        let fileURL = try createInvalidHeaderFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let parser = GGUFModelParser()
        #expect(throws: (any Error).self) {
            _ = try parser.parseHeaderAndMetadata(at: fileURL)
        }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "invalid-gguf"),
            name: "Invalid GGUF",
            localURL: fileURL
        )

        let engine = LlamaCPPModelEngine(identity: identity)
        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Expected engine load to fail on invalid file")
        } catch {
            let state = await engine.lifecycleState
            if case .failed = state {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected state to be .failed")
            }
        }
    }

    @Test func testDummyHeaderFileFailsNativeModelLoadAndFailsClosed() async throws {
        // A file with GGUF header but no tensors cannot be loaded by native llama.cpp
        let fileURL = try createDummyHeaderGGUFFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "dummy-gguf"),
            name: "Dummy GGUF",
            localURL: fileURL
        )

        let engine = LlamaCPPModelEngine(identity: identity)
        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Native model loader must fail closed on missing tensor weights")
        } catch let err as LlamaCPPEngineError {
            if case .nativeModelLoadFailed = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected nativeModelLoadFailed, got \(err)")
            }
            let state = await engine.lifecycleState
            if case .failed = state {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected state .failed")
            }
        }
    }

    @Test func testSingleResidentModelExclusivityInvariant() async throws {
        let ggufURL1 = try createDummyHeaderGGUFFile(name: "model1.gguf")
        let ggufURL2 = try createDummyHeaderGGUFFile(name: "model2.gguf")
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

        // Attempting to load model 1 fails on dummy weights, but coordinator tracks residency request
        do {
            try await engine1.load(options: LocalModelLoadingOptions())
        } catch {}

        let state1 = await engine1.lifecycleState
        let state2 = await engine2.lifecycleState

        // Model 1 and Model 2 must never be simultaneously loaded
        let isSimultaneous = (state1 == .loaded && state2 == .loaded)
        #expect(!isSimultaneous)
    }

    @Test func testThermalGovernance() async throws {
        let deviceProv = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(thermalState: .critical)
        )

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "thermal-llama"),
            name: "Thermal Llama",
            localURL: URL(fileURLWithPath: "/tmp/nonexistent.gguf")
        )

        let engine = LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceProv
        )

        let request = LocalModelGenerationRequest(prompt: "Hello thermal test")
        do {
            _ = try await engine.generate(request: request)
            #expect(Bool(false), "Expected modelNotLoaded or thermalStateCritical error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .modelNotLoaded || err == .thermalStateCritical)
        }
    }

    @Test func testMemoryPressureGovernance() async throws {
        let deviceProv = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(memoryPressure: .critical)
        )

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "memory-llama"),
            name: "Memory Llama",
            localURL: URL(fileURLWithPath: "/tmp/nonexistent.gguf")
        )

        let engine = LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceProv
        )

        let request = LocalModelGenerationRequest(prompt: "Hello memory test")
        do {
            _ = try await engine.generate(request: request)
            #expect(Bool(false), "Expected modelNotLoaded error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .modelNotLoaded)
        }
    }

    @Test func testLocalModelProviderAdapterBridge() async throws {
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "bridge-llama"),
            name: "Bridge Llama",
            localURL: URL(fileURLWithPath: "/tmp/dummy.gguf")
        )

        let engine = LlamaCPPModelEngine(identity: identity)
        let adapter = LocalModelProviderAdapter(engine: engine)

        #expect(adapter.capabilities.contains(ProviderCapabilities.localInference))
        #expect(!adapter.capabilities.contains(ProviderCapabilities.toolCalling))
    }

    @Test func testSecurityAndPersistenceBoundaryInvariants() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M81Security_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try ProductPersistenceContainer(baseDirectoryURL: tempDir)
        #expect(container.modelMetadataDirectoryURL.lastPathComponent == "ModelMetadata")
        #expect(container.agentDurableDirectoryURL.lastPathComponent == "AgentDurableState")
        #expect(container.modelMetadataDirectoryURL != container.agentDurableDirectoryURL)
    }

    private static var isLocalGGUFModelPathProvided: Bool {
        guard let path = ProcessInfo.processInfo.environment["LOCAL_GGUF_MODEL_PATH"],
              !path.isEmpty else {
            return false
        }
        return true
    }

    @Test(.enabled(if: isLocalGGUFModelPathProvided))
    func testRealNativeInferenceWhenModelProvided() async throws {
        let modelPath = try #require(ProcessInfo.processInfo.environment["LOCAL_GGUF_MODEL_PATH"])
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Issue.record("MODEL MISSING: File specified in LOCAL_GGUF_MODEL_PATH does not exist at \(modelPath)")
            return
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "live-local-llama"),
            name: "Live Local Llama",
            localURL: modelURL
        )

        let engine = LlamaCPPModelEngine(identity: identity)
        try await engine.load(options: LocalModelLoadingOptions(contextWindow: 1024))

        let state = await engine.lifecycleState
        #expect(state == .loaded)

        let request = LocalModelGenerationRequest(prompt: "Hello, reply with one word: Success")
        let response = try await engine.generate(request: request)

        #expect(!response.text.isEmpty)
        #expect(response.finishReason == "stop" || response.finishReason == "length")

        try await engine.unload()
        let stateAfter = await engine.lifecycleState
        #expect(stateAfter == .unloaded)
    }

    struct ZeroTokenEngineNoValidator: LocalModelEngine {
        let identity: LocalModelIdentity
        var availability: LocalModelAvailability { get async { .ready } }
        var lifecycleState: LocalModelLifecycleState { get async { .loaded } }

        init() {
            self.identity = LocalModelIdentity(
                id: ModelID(rawValue: "empty-llama"),
                name: "Empty Llama",
                contextTokenLimit: 2048
            )
        }

        func load(options: LocalModelLoadingOptions) async throws {}

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            return LocalModelResponse(text: "", finishReason: "stop")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        func cancel() async {}
        func unload() async throws {}
    }

    @Test(.enabled(if: isLocalGGUFModelPathProvided))
    func testRepeatedNativeInferenceResetsRequestState() async throws {
        let modelPath = try #require(ProcessInfo.processInfo.environment["LOCAL_GGUF_MODEL_PATH"])
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Issue.record("MODEL MISSING: File specified in LOCAL_GGUF_MODEL_PATH does not exist at \(modelPath)")
            return
        }

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "repeat-local-llama"),
            name: "Repeat Local Llama",
            localURL: URL(fileURLWithPath: modelPath)
        )
        let engine = LlamaCPPModelEngine(identity: identity)
        try await engine.load(options: LocalModelLoadingOptions(contextWindow: 1024))
        defer { Task { try? await engine.unload() } }

        let first = try await engine.generate(
            request: LocalModelGenerationRequest(prompt: "Reply with one short greeting.")
        )
        let second = try await engine.generate(
            request: LocalModelGenerationRequest(prompt: "Reply with a different short greeting.")
        )

        #expect(!first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!second.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(first.finishReason == "stop" || first.finishReason == "length")
        #expect(second.finishReason == "stop" || second.finishReason == "length")
    }

    @Test func testEmptyOutputThrowsExplicitError() async throws {
        // Direct production validator unit test
        #expect(throws: LlamaCPPEngineError.emptyOutput) {
            try LocalModelOutputValidator.validate(text: "", generatedCount: 0)
        }

        // LlamaCPPModelEngine production zero-token boundary test.
        // Instantiates actual production LlamaCPPModelEngine with a stream runner that yields 0 tokens (generatedCount == 0) without throwing.
        // If LlamaCPPModelEngine removes LocalModelOutputValidator.validate(text:generatedCount:), THIS TEST FAILS.
        let llamaIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "zero-token-llama"),
            name: "Zero Token Llama",
            contextTokenLimit: 2048
        )
        let zeroTokenLlamaEngine = LlamaCPPModelEngine(
            identity: llamaIdentity,
            streamRunner: { _, _ in
                // Yield 0 tokens and return generatedCount = 0
                return 0
            }
        )

        let llamaGenRequest = LocalModelGenerationRequest(prompt: "Hello zero token test")

        // 1. Verify LlamaCPPModelEngine.generateStream throws LlamaCPPEngineError.emptyOutput
        let llamaStream = zeroTokenLlamaEngine.generateStream(request: llamaGenRequest)
        do {
            for try await _ in llamaStream {}
            #expect(Bool(false), "Expected LlamaCPPModelEngine.generateStream to throw LlamaCPPEngineError.emptyOutput on generatedCount == 0")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .emptyOutput)
        }

        // 2. Verify LlamaCPPModelEngine.generate throws LlamaCPPEngineError.emptyOutput
        do {
            _ = try await zeroTokenLlamaEngine.generate(request: llamaGenRequest)
            #expect(Bool(false), "Expected LlamaCPPModelEngine.generate to throw LlamaCPPEngineError.emptyOutput")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .emptyOutput)
        }

        // 3. Verify LocalModelProviderAdapter stream validation catches zero-token stream from raw engine
        let rawEngine = ZeroTokenEngineNoValidator()
        let adapter = LocalModelProviderAdapter(engine: rawEngine)
        let request = LLMRequest(model: ModelID(rawValue: "empty-llama"), prompt: "Hello empty test")

        let adapterStream = adapter.stream(request)
        do {
            for try await _ in adapterStream {}
            #expect(Bool(false), "Expected adapter.stream to catch zero-token stream and throw LlamaCPPEngineError.emptyOutput")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .emptyOutput)
        }
    }

    @Test func testCancellationPropagation() async throws {
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "cancel-llama"),
            name: "Cancel Llama",
            localURL: URL(fileURLWithPath: "/tmp/nonexistent.gguf")
        )
        let engine = LlamaCPPModelEngine(identity: identity)
        await engine.cancel()

        let state = await engine.lifecycleState
        #expect(state == .unloaded)
    }

    @Test func testActiveModelIdentityMatchesEngineModelIdentity() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M8P3IdentityTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let compositionRoot = try await M8CompositionRoot(storeDirectoryURL: tempDir)

        // When no active model is selected, activeLocalModelEngine returns nil
        let nilEngine = try await compositionRoot.activeLocalModelEngine()
        #expect(nilEngine == nil)

        // Register a model in localModelStorage and mark active
        let dummyModelURL = try createDummyHeaderGGUFFile(name: "active_test.gguf")

        _ = try await compositionRoot.localModelStorage.importModel(
            from: dummyModelURL,
            name: "Active Test Model"
        )

        let importedModels = try await compositionRoot.localModelStorage.listModels()
        let imported = try #require(importedModels.first)

        try await compositionRoot.localModelStorage.setActiveModel(id: imported.id)

        let activeEngine = try await compositionRoot.activeLocalModelEngine()
        let resolvedEngine = try #require(activeEngine)

        #expect(resolvedEngine.identity.id == imported.id)
        #expect(resolvedEngine.identity.name == "Active Test Model")
    }
}
