import Foundation
import Testing
import PAComposition
import PAProviders
import PAProvidersLocal
import PAStorageModels
import PAKernel

@Suite("Dynamic active provider routing")
struct DynamicActiveProviderRoutingTests {
    @Test func remoteInferenceFailsClosedWhenNetworkPermissionIsDenied() async throws {
        struct DenyNetworkPolicy: PolicyEvaluating {
            func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
                intent.capabilities.contains(.network) ? .deny("network disabled") : .allow()
            }
        }
        let suiteName = "DynamicActiveProviderRoutingTests.denied.\\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: suiteName))
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set("remote", forKey: "provider.execution.mode")
        settings.set(true, forKey: "provider.remote.enabled")
        settings.set(false, forKey: "privacy.localOnly")
        let coordinator = LocalModelRuntimeCoordinator(storage: FailingLocalModelStorage(), deviceCapabilityProvider: DefaultDeviceCapabilityProvider())
        let provider = DynamicActiveProvider(fallbackProvider: DeterministicFakeProvider(), coordinator: coordinator, settings: settings, policy: DenyNetworkPolicy())
        await #expect(throws: ProviderRuntimeError.authorizationFailure) {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "must not call remote"))
        }
    }
    @Test func remoteInferenceFailsClosedWhenNetworkPolicyIsMissing() async throws {
        let suiteName = "DynamicActiveProviderRoutingTests.missing-policy.\\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: suiteName))
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set("remote", forKey: "provider.execution.mode")
        settings.set(true, forKey: "provider.remote.enabled")
        settings.set(false, forKey: "privacy.localOnly")

        let coordinator = LocalModelRuntimeCoordinator(
            storage: FailingLocalModelStorage(),
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )
        let provider = DynamicActiveProvider(
            fallbackProvider: DeterministicFakeProvider(),
            coordinator: coordinator,
            settings: settings
        )
        await #expect(throws: ProviderRuntimeError.authorizationFailure) {
            _ = try await provider.complete(
                LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "must not bypass policy")
            )
        }
    }

    @Test func remoteStreamingDoesNotResolveLocalModelStorage() async throws {
        let suiteName = "DynamicActiveProviderRoutingTests.\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: suiteName))
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set("remote", forKey: "provider.execution.mode")
        settings.set(true, forKey: "provider.remote.enabled")
        settings.set(false, forKey: "privacy.localOnly")

        let coordinator = LocalModelRuntimeCoordinator(
            storage: FailingLocalModelStorage(),
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider()
        )
        let provider = DynamicActiveProvider(
            fallbackProvider: DeterministicFakeProvider(),
            coordinator: coordinator,
            settings: settings,
            policy: AllowNetworkPolicy()
        )
        let request = LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "route remote")

        var sawFallbackDelta = false
        for try await event in provider.stream(request) {
            if case .delta("ok") = event {
                sawFallbackDelta = true
            }
        }

        #expect(sawFallbackDelta)
    }
}

private struct AllowNetworkPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .allow()
    }
}

private struct FailingLocalModelStorage: LocalModelStorage {
    private var failure: LocalModelStorageError {
        .storageCorrupt("Local storage must not be accessed in remote mode")
    }

    func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor { throw failure }
    func listModels() async throws -> [LocalModelDescriptor] { throw failure }
    func getModel(id: ModelID) async throws -> LocalModelDescriptor? { throw failure }
    func deleteModel(id: ModelID) async throws { throw failure }
    func setActiveModel(id: ModelID?) async throws { throw failure }
    func activeModelID() async throws -> ModelID? { throw failure }
    func activeModelDescriptor() async throws -> LocalModelDescriptor? { throw failure }
    func modelFileURL(for id: ModelID) async throws -> URL? { throw failure }
}


private final class StreamLoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var loads = 0

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loaded
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loads
    }

    func markLoaded() {
        lock.lock()
        defer { lock.unlock() }
        loaded = true
        loads += 1
    }

    func markUnloaded() {
        lock.lock()
        defer { lock.unlock() }
        loaded = false
    }
}

private final class StreamLoadFixtureEngine: LocalModelEngine, @unchecked Sendable {
    let identity: LocalModelIdentity
    private let recorder: StreamLoadRecorder

    init(identity: LocalModelIdentity, recorder: StreamLoadRecorder) {
        self.identity = identity
        self.recorder = recorder
    }

    var availability: LocalModelAvailability {
        get async { .ready }
    }

    var lifecycleState: LocalModelLifecycleState {
        get async { recorder.isLoaded ? .loaded : .unloaded }
    }

    func load(options: LocalModelLoadingOptions) async throws {
        recorder.markLoaded()
    }

    func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
        guard recorder.isLoaded else { throw LlamaCPPEngineError.modelNotLoaded }
        return LocalModelResponse(text: "local answer")
    }

    func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            guard recorder.isLoaded else {
                continuation.finish(throwing: LlamaCPPEngineError.modelNotLoaded)
                return
            }
            continuation.yield(LocalModelStreamChunk(textDelta: "local answer"))
            continuation.finish()
        }
    }

    func cancel() async {}

    func unload() async throws {
        recorder.markUnloaded()
    }
}

private struct StreamLoadFixtureStorage: LocalModelStorage {
    let descriptor: LocalModelDescriptor
    let fileURL: URL

    func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor {
        throw LocalModelStorageError.storageCorrupt("Import is not part of this fixture")
    }
    func listModels() async throws -> [LocalModelDescriptor] { [descriptor] }
    func getModel(id: ModelID) async throws -> LocalModelDescriptor? {
        descriptor.id == id ? descriptor : nil
    }
    func deleteModel(id: ModelID) async throws {}
    func setActiveModel(id: ModelID?) async throws {}
    func activeModelID() async throws -> ModelID? { descriptor.id }
    func activeModelDescriptor() async throws -> LocalModelDescriptor? { descriptor }
    func modelFileURL(for id: ModelID) async throws -> URL? {
        descriptor.id == id ? fileURL : nil
    }
}

extension DynamicActiveProviderRoutingTests {
    @Test func localStreamingLoadsTheActiveModelOnlyWhenInferenceStarts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicActiveProviderRoutingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let modelURL = root.appendingPathComponent("fixture.gguf")
        try Data([0x47, 0x47, 0x55, 0x46]).write(to: modelURL)

        let modelID = ModelID(rawValue: "stream-fixture")
        let descriptor = LocalModelDescriptor(
            id: modelID,
            name: "Streaming fixture",
            filename: "fixture.gguf",
            fileSizeBytes: 4
        )
        let recorder = StreamLoadRecorder()
        let coordinator = LocalModelRuntimeCoordinator(
            storage: StreamLoadFixtureStorage(descriptor: descriptor, fileURL: modelURL),
            deviceCapabilityProvider: DefaultDeviceCapabilityProvider(),
            engineFactory: { identity, _ in
                StreamLoadFixtureEngine(identity: identity, recorder: recorder)
            }
        )
        let suiteName = "DynamicActiveProviderRoutingTests.local.\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: suiteName))
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set("local", forKey: "provider.execution.mode")
        settings.set(false, forKey: "provider.remote.enabled")

        let provider = DynamicActiveProvider(
            fallbackProvider: DeterministicFakeProvider(),
            coordinator: coordinator,
            settings: settings
        )
        #expect(recorder.loadCount == 0)

        var receivedAnswer = false
        for try await event in provider.stream(
            LLMRequest(model: modelID, prompt: "Think about this")
        ) {
            if case .completed(let response) = event {
                receivedAnswer = response.text == "local answer"
            }
        }

        #expect(receivedAnswer)
        #expect(recorder.loadCount == 1)
        #expect(recorder.isLoaded)
    }
}
