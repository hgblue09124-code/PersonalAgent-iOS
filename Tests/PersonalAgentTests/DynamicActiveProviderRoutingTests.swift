import Foundation
import Testing
import PAComposition
import PAProviders
import PAStorageModels
import PAKernel

@Suite("Dynamic active provider routing")
struct DynamicActiveProviderRoutingTests {
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
            settings: settings
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
