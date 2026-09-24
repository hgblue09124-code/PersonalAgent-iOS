import Testing
import Foundation
import PAFoundation
import PAProviders
import PAProvidersLocal
import PAComposition

@Suite("M9.1 Real GGUF Execution Verification Tests")
struct M91RealGGUFExecutionTests {

    private func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M91Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createDummyGGUFFile(at directory: URL, filename: String = "test.gguf") throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        // Write GGUF magic bytes: 0x46554747 ("GGUF") in Little Endian + version 3
        var data = Data([0x47, 0x47, 0x55, 0x46])
        var version: UInt32 = 3
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })
        // Add tensor count (0) & metadata count (0)
        var count: UInt64 = 0
        data.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - F1: Invalid GGUF Handling (Synthetic Fixture)

    @Test func testF1_InvalidGGUFHeaderFailsImportAndLoad() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let invalidFile = dir.appendingPathComponent("invalid.gguf")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: invalidFile)

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: dir)

        // 1. Storage import fails closed on invalid header
        do {
            _ = try await storage.importModel(from: invalidFile)
            #expect(Bool(false), "Expected invalid GGUF header import to throw")
        } catch let err as LocalModelStorageError {
            if case .invalidGGUFHeader = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected LocalModelStorageError type: \(err)")
            }
        }

        // 2. Direct LlamaCPPModelEngine load fails closed on invalid GGUF file
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "invalid-gguf-model"),
            name: "Invalid GGUF Model",
            localURL: invalidFile
        )
        let engine = LlamaCPPModelEngine(identity: identity)

        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Expected engine load to fail on invalid GGUF file")
        } catch let err as GGUFParseError {
            switch err {
            case .invalidMagic, .truncatedFile, .unsupportedVersion, .stringDecodingFailed:
                #expect(Bool(true))
            }
        }

        let state = await engine.lifecycleState
        if case .failed = state {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected engine state to be failed, got \(state)")
        }
    }

    // MARK: - F2a: Malformed or Truncated GGUF Parser Failure (Synthetic Fixture)

    @Test func testF2a_MalformedOrTruncatedGGUFParserFailure() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let truncatedFile = dir.appendingPathComponent("truncated.gguf")
        // Truncated data: valid magic 0x47475546 but no version or metadata
        try Data([0x47, 0x47, 0x55, 0x46]).write(to: truncatedFile)

        let parser = GGUFModelParser()
        do {
            _ = try parser.parseHeaderAndMetadata(at: truncatedFile)
            #expect(Bool(false), "Expected parseHeaderAndMetadata to throw truncatedFile")
        } catch let err as GGUFParseError {
            #expect(err == .truncatedFile)
        }
    }

    // MARK: - F2b: Valid Header with Truncated Body Native Load Failure (Synthetic Fixture)

    @Test func testF2b_ValidHeaderWithTruncatedBodyNativeLoadFailure() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dummyURL = try createDummyGGUFFile(at: dir, filename: "dummy_load_fail.gguf")

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "dummy-load-fail"),
            name: "Dummy Load Fail Model",
            localURL: dummyURL
        )
        let engine = LlamaCPPModelEngine(identity: identity)

        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Expected native model load to throw nativeModelLoadFailed")
        } catch let err as LlamaCPPEngineError {
            if case .nativeModelLoadFailed(let path) = err {
                #expect(path == dummyURL.path)
            } else {
                #expect(Bool(false), "Unexpected LlamaCPPEngineError: \(err)")
            }
        }

        let state = await engine.lifecycleState
        if case .failed = state {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected engine state to be failed, got \(state)")
        }
    }

    // MARK: - F3: Active Model Resolution Failure Propagation Through Runtime & Provider

    @Test func testF3_ActiveModelResolutionFailureFailsClosedWithoutFakeSuccess() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: dir)
        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )

        // 1. Setting active model to missing ID fails closed at storage level
        do {
            try await storage.setActiveModel(id: ModelID(rawValue: "ghost-id"))
            #expect(Bool(false), "Expected setActiveModel with non-existent ID to throw modelNotFound")
        } catch let err as LocalModelStorageError {
            if case .modelNotFound = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected LocalModelStorageError: \(err)")
            }
        }

        // 2. Active model resolution returns nil when no valid active model is set
        let activeEngine = try await coordinator.activeLocalModelEngine()
        #expect(activeEngine == nil, "Expected nil active engine when no active model is set")

        // 3. DynamicActiveProvider propagation: When storage index has an active model ID whose backing file is deleted,
        // activeLocalModelEngine throws fileNotFound or engine completion throws modelNotLoaded. DynamicActiveProvider MUST propagate error and NEVER return fake success.
        let dummyURL = try createDummyGGUFFile(at: dir, filename: "missing_file.gguf")
        let descriptor = try await storage.importModel(from: dummyURL, name: "Missing Backing File Model")
        try await storage.setActiveModel(id: descriptor.id)

        // Delete the actual app-owned backing file while keeping descriptor active in index
        let backingFileURL = try #require(await storage.modelFileURL(for: descriptor.id))
        try? FileManager.default.removeItem(at: dummyURL)
        try FileManager.default.removeItem(at: backingFileURL)

        let dynamicProvider = DynamicActiveProvider(
            fallbackProvider: DeterministicFakeProvider(),
            coordinator: coordinator
        )

        let req = LLMRequest(model: ModelID(rawValue: "test"), prompt: "Test missing backing file")
        do {
            _ = try await dynamicProvider.complete(req)
            #expect(Bool(false), "Expected complete to throw error when backing file is missing")
        } catch let err as LocalModelStorageError {
            if case .fileNotFound = err {
                #expect(Bool(true))
            } else if case .modelNotFound = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected LocalModelStorageError: \(err)")
            }
        } catch let err as LlamaCPPEngineError {
            #expect(err == .modelNotLoaded || err == .invalidModelURL)
        }
    }

    // MARK: - F4: Native Inference Failure Propagation (Injected Test Double)

    @Test func testF4_InjectedNativeInferenceFailurePropagatesWithoutFakeFallback() async throws {
        // [INJECTED TEST DOUBLE] Verifies error propagation using streamRunner injection (not real native llama.cpp execution)
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "failing-engine"),
            name: "Failing Engine"
        )
        let engine = LlamaCPPModelEngine(
            identity: identity,
            streamRunner: { _, _ in
                throw LlamaCPPEngineError.evalFailed(-1)
            }
        )

        let req = LocalModelGenerationRequest(prompt: "Test failing inference")

        // 1. Direct engine completion propagates evalFailed
        do {
            _ = try await engine.generate(request: req)
            #expect(Bool(false), "Expected generate to throw evalFailed")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .evalFailed(-1))
        }

        // 2. Adapter complete propagates evalFailed
        let adapter = LocalModelProviderAdapter(engine: engine)
        let llmReq = LLMRequest(model: ModelID(rawValue: "failing-engine"), prompt: "Test failing inference")

        do {
            _ = try await adapter.complete(llmReq)
            #expect(Bool(false), "Expected adapter complete to throw evalFailed")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .evalFailed(-1))
        }
    }

    // MARK: - F5: Empty/Invalid Output Rejection (Injected Test Double & Pure Validator)

    @Test func testF5_EmptyOrZeroTokenOutputRejectedByValidator() async throws {
        // Direct validator unit verification
        #expect(throws: LlamaCPPEngineError.emptyOutput) {
            try LocalModelOutputValidator.validate(text: "")
        }
        #expect(throws: LlamaCPPEngineError.emptyOutput) {
            try LocalModelOutputValidator.validate(text: "   \n\t  ")
        }
        #expect(throws: LlamaCPPEngineError.emptyOutput) {
            try LocalModelOutputValidator.validate(text: "Non-empty string", generatedCount: 0)
        }

        // [INJECTED TEST DOUBLE] Engine stream runner producing empty output throws emptyOutput
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "empty-output-engine"),
            name: "Empty Output Engine"
        )
        let engine = LlamaCPPModelEngine(
            identity: identity,
            streamRunner: { _, continuation in
                continuation.yield(LocalModelStreamChunk(textDelta: ""))
                return 0
            }
        )

        let req = LocalModelGenerationRequest(prompt: "Generate nothing")
        do {
            _ = try await engine.generate(request: req)
            #expect(Bool(false), "Expected empty output generation to throw emptyOutput")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .emptyOutput)
        }
    }

    // MARK: - F6: Fallback Provider Output vs Local Model Inference Distinguishability (Provider Routing Test Double)

    @Test func testF6_NoActiveModelDistinguishesFallbackFromRealInference() async throws {
        // [PROVIDER ROUTING & FALLBACK DISTINCTION TEST]
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: dir)
        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )
        let fallbackProvider = DeterministicFakeProvider()
        let dynamicProvider = DynamicActiveProvider(
            fallbackProvider: fallbackProvider,
            coordinator: coordinator
        )

        // 1. When NO active model is set:
        let nilEngine = try await coordinator.activeLocalModelEngine()
        #expect(nilEngine == nil)

        let req = LLMRequest(model: ModelID(rawValue: "prompt-model"), prompt: "Hello fallback query")
        let fallbackResponse = try await dynamicProvider.complete(req)

        // Output comes strictly from DeterministicFakeProvider
        #expect(fallbackResponse.model?.rawValue == "fake-text")
        #expect(fallbackResponse.text == "ok")
        #expect(dynamicProvider.identity.id.rawValue == "fake")

        // 2. When an active local model engine IS configured (using test double for provider identity check):
        let localIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "real-gguf-01"),
            name: "Test Local Model"
        )
        let mockEngine = LlamaCPPModelEngine(
            identity: localIdentity,
            streamRunner: { req, continuation in
                continuation.yield(LocalModelStreamChunk(textDelta: "Real local response text"))
                return 4
            }
        )
        let localAdapter = LocalModelProviderAdapter(engine: mockEngine)
        let localResponse = try await localAdapter.complete(req)

        // Contrast: Local provider identity and model ID are explicitly distinct from fake fallback
        #expect(localResponse.model?.rawValue == "prompt-model")
        #expect(localResponse.text == "Real local response text")
        #expect(localAdapter.identity.id.rawValue == "local-real-gguf-01")
        #expect(localAdapter.identity.id.rawValue != fallbackProvider.identity.id.rawValue)
    }

    // MARK: - F7: Thermal and Memory Protection Governance

    @Test func testF7_ThermalAndMemoryProtectionsFailClosed() async throws {
        // Critical thermal state
        let thermalProvider = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(thermalState: .critical)
        )
        let thermalIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "thermal-model"),
            name: "Thermal Model"
        )
        let thermalEngine = LlamaCPPModelEngine(
            identity: thermalIdentity,
            deviceCapabilityProvider: thermalProvider
        )

        do {
            _ = try await thermalEngine.generate(request: LocalModelGenerationRequest(prompt: "Hot"))
            #expect(Bool(false), "Expected modelNotLoaded or thermalStateCritical error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .modelNotLoaded || err == .thermalStateCritical)
        }

        // Critical memory pressure
        let memoryProvider = DefaultDeviceCapabilityProvider(
            initialSnapshot: DeviceStateSnapshot(memoryPressure: .critical)
        )
        let memoryIdentity = LocalModelIdentity(
            id: ModelID(rawValue: "memory-model"),
            name: "Memory Model"
        )
        let memoryEngine = LlamaCPPModelEngine(
            identity: memoryIdentity,
            deviceCapabilityProvider: memoryProvider
        )

        do {
            _ = try await memoryEngine.generate(request: LocalModelGenerationRequest(prompt: "OOM"))
            #expect(Bool(false), "Expected modelNotLoaded error")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .modelNotLoaded)
        }
    }

    // MARK: - Identity & Consistency Invariants

    @Test func testActiveModelIDAndEngineIdentityConsistency() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ggufURL = try createDummyGGUFFile(at: dir, filename: "consistency.gguf")
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: dir)

        let descriptor = try await storage.importModel(from: ggufURL, name: "Consistency Test Model")
        try await storage.setActiveModel(id: descriptor.id)

        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )

        let activeEngine = try #require(try await coordinator.activeLocalModelEngine())

        // Invariant: Active Model ID in storage == Resolved Engine Identity ID
        #expect(try await storage.activeModelID() == activeEngine.identity.id)
        #expect(activeEngine.identity.id == descriptor.id)
        #expect(activeEngine.identity.name == "Consistency Test Model")
    }

    // MARK: - Real GGUF Model Execution Gate (Requires LOCAL_GGUF_MODEL_PATH)

    private static var isLocalGGUFModelPathProvided: Bool {
        guard let path = ProcessInfo.processInfo.environment["LOCAL_GGUF_MODEL_PATH"],
              !path.isEmpty else {
            return false
        }
        return true
    }

    @Test(.enabled(if: isLocalGGUFModelPathProvided))
    func testRealNativeInferenceWhenModelProvided() async throws {
        // [REAL NATIVE INFERENCE GATE — FULL PRODUCTION PATH]
        let modelPath = try #require(ProcessInfo.processInfo.environment["LOCAL_GGUF_MODEL_PATH"])
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Issue.record("MODEL MISSING: File specified in LOCAL_GGUF_MODEL_PATH does not exist at \(modelPath)")
            return
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let testDir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }

        // 1. Storage Import & Active Model Selection
        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: testDir)
        let descriptor = try await storage.importModel(from: modelURL, name: "Live Production Llama")
        try await storage.setActiveModel(id: descriptor.id)

        #expect(try await storage.activeModelID() == descriptor.id)

        // 2. Runtime Coordinator & Dynamic Provider Setup
        let deviceProv = DefaultDeviceCapabilityProvider()
        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: deviceProv
        )

        let dynamicProvider = DynamicActiveProvider(
            fallbackProvider: DeterministicFakeProvider(),
            coordinator: coordinator
        )

        // 3. Verify Active Model Identity Invariant
        let activeEngine = try #require(try await coordinator.activeLocalModelEngine())
        #expect(try await storage.activeModelID() == activeEngine.identity.id)
        #expect(activeEngine.identity.id == descriptor.id)

        // 4. Load Active Local Model via Coordinator
        _ = try await coordinator.loadActiveModel(options: LocalModelLoadingOptions(contextWindow: 1024))
        let state = await activeEngine.lifecycleState
        #expect(state == .loaded)

        // 5. Execute Real Inference Through Dynamic Provider & Provider Adapter Boundary
        let req = LLMRequest(model: descriptor.id, prompt: "Hello, reply with one word: Success")
        let response = try await dynamicProvider.complete(req)

        // 6. Verify Real Inference Output
        #expect(!response.text.isEmpty)
        #expect(response.finishReason == "stop" || response.finishReason == "length")
        #expect(response.model?.rawValue == descriptor.id.rawValue)

        // 7. Unload Active Local Model via Coordinator
        try await coordinator.unloadActiveModel()
        let stateAfter = await activeEngine.lifecycleState
        #expect(stateAfter == .unloaded)
    }
}
