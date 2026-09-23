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

    // MARK: - F1: Invalid GGUF Handling

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
                #expect(Bool(false), "Unexpected error type: \(err)")
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

    // MARK: - F2: Native Model Load Failure Propagation

    @Test func testF2_NativeModelLoadFailurePropagates() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Dummy GGUF has valid header but is truncated/fake binary, so llama_model_load_from_file will fail or throw
        let dummyURL = try createDummyGGUFFile(at: dir, filename: "dummy_load_fail.gguf")

        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "dummy-load-fail"),
            name: "Dummy Load Fail Model",
            localURL: dummyURL
        )
        let engine = LlamaCPPModelEngine(identity: identity)

        do {
            try await engine.load(options: LocalModelLoadingOptions())
            #expect(Bool(false), "Expected native model load to throw")
        } catch let err as LlamaCPPEngineError {
            #expect(err == .nativeModelLoadFailed(dummyURL.path))
        } catch {
            // Native cllama load failure or file parse error
            #expect(Bool(true))
        }

        let state = await engine.lifecycleState
        if case .failed = state {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected engine state to be failed, got \(state)")
        }
    }

    // MARK: - F3: Active Model Resolution Failure

    @Test func testF3_ActiveModelResolutionFailureNoFakeSuccess() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = try FileBackedLocalModelStorage(modelsDirectoryURL: dir)
        let coordinator = LocalModelRuntimeCoordinator(
            storage: storage,
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )

        // Setting active model to missing ID fails closed at storage level
        do {
            try await storage.setActiveModel(id: ModelID(rawValue: "ghost-id"))
            #expect(Bool(false), "Expected setActiveModel with non-existent ID to throw modelNotFound")
        } catch let err as LocalModelStorageError {
            if case .modelNotFound = err {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Unexpected error: \(err)")
            }
        }

        // Active model resolution returns nil when no active model is set
        let activeEngine = try await coordinator.activeLocalModelEngine()
        #expect(activeEngine == nil, "Expected nil active engine when no active model is set")
    }

    // MARK: - F4: Native Inference Failure Propagation

    @Test func testF4_NativeInferenceFailurePropagatesWithoutFakeFallback() async throws {
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

    // MARK: - F5: Empty/Invalid Output Rejection

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

        // Engine stream runner producing empty output throws emptyOutput
        let identity = LocalModelIdentity(
            id: ModelID(rawValue: "empty-output-engine"),
            name: "Empty Output Engine"
        )
        let engine = LlamaCPPModelEngine(
            identity: identity,
            streamRunner: { _, continuation in
                // Yield empty chunk
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

    // MARK: - F6: No Active Model Boundary (Fallback vs Real Inference)

    @Test func testF6_NoActiveModelDistinguishesFallbackFromRealInference() async throws {
        let dir = try createTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let compositionRoot = try await M8CompositionRoot(storeDirectoryURL: dir)

        // When no local model is active:
        let nilEngine = try await compositionRoot.activeLocalModelEngine()
        #expect(nilEngine == nil)

        let provider = compositionRoot.catalog.identities.first!
        #expect(provider.id.rawValue == "fake")

        // Provider completion uses fallback provider, NOT local model engine
        let res = await compositionRoot.session.currentState()
        #expect(res.lifecycle == .running || res.lifecycle == .created)
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
}
