import Foundation
import SwiftUI
import PAFoundation
import PAKernel
import PAComposition
import PAArchitecture
import PAProviders

@MainActor
final class KernelSession: ObservableObject {
    let composition: M8CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?
    @Published var providerID: String
    @Published var providerRoute: ProviderRoute
    @Published var providerLifecycle: String
    @Published var providerConnectionState: String
    @Published var providerModels: [ModelIdentity]
    @Published var selectedProviderModelID: ModelID?
    @Published var moduleIDs: [String]

    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelID: ModelID?
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineState: LocalModelLifecycleState
    @Published var remoteModels: [RemoteModel] = []
    @Published var isUpdatingModelCatalog = false
    @Published var isDownloadingModelPack = false
    @Published var modelCatalogUpdatedAt: Date?
    @Published var modelDownloadProgress: Double = 0
    @Published var executionProgress: AgentExecutionProgress?
    @Published var executionTrace: [AgentExecutionProgress] = []
    @Published var executionResult: String?
    @Published var chatPhase: String?
    private var lastSubmittedTask: String?

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerRoute = .remote
        self.providerLifecycle = "unknown"
        self.providerConnectionState = "Not tested"
        self.providerModels = []
        self.selectedProviderModelID = nil
        self.moduleIDs = []
        self.installedModels = []
        self.activeModelID = nil
        self.activeModelDescriptor = nil
        self.activeEngineState = .unloaded
        self.chatPhase = nil
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerRoute = await composition.selectedProviderRoute()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
        if providerConnectionState == "Not tested" || providerConnectionState == "Connected" {
            providerConnectionState = await hasProviderAPIKey() ? providerConnectionState : "Not configured"
        }
        providerModels = await composition.availableProviderModels()
        selectedProviderModelID = await composition.selectedProviderModelID()
        moduleIDs = await composition.registeredModuleIDs()

        let storage = composition.localModelStorage
        do {
            installedModels = try await storage.listModels()
            activeModelID = try await storage.activeModelID()
            activeModelDescriptor = try await storage.activeModelDescriptor()
        } catch {
            installedModels = []
            activeModelID = nil
            activeModelDescriptor = nil
            lastError = String(describing: error)
        }

        do {
            if let engine = try await composition.activeLocalModelEngine() {
                activeEngineState = await engine.lifecycleState
            } else {
                activeEngineState = .unloaded
            }
        } catch {
            activeEngineState = .failed(reason: error.localizedDescription)
            lastError = String(describing: error)
        }
    }

    func updateModelCatalog() async {
        guard !isUpdatingModelCatalog else { return }
        isUpdatingModelCatalog = true
        lastError = nil
        defer { isUpdatingModelCatalog = false }

        do {
            let catalog = try await RemoteModelCatalogClient.fetch()
            remoteModels = catalog.models
            modelCatalogUpdatedAt = Date()
        } catch {
            lastError = "Model catalog update failed: \(error.localizedDescription)"
        }
    }

    func downloadModel(_ model: RemoteModel) async {
        guard !isDownloadingModelPack else { return }
        isDownloadingModelPack = true
        modelDownloadProgress = 0
        lastError = nil
        defer { isDownloadingModelPack = false }

        do {
            let temporaryURL = try await RemoteModelCatalogClient.download(model)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            _ = try await composition.localModelStorage.importModel(from: temporaryURL, name: model.name)
            modelDownloadProgress = 1
            await refresh()
        } catch {
            lastError = "Model download failed: \(error.localizedDescription)"
        }
    }

    func downloadTestPack() async {
        guard !isDownloadingModelPack else { return }
        let models = remoteModels.filter(\.testPack)
        guard !models.isEmpty else {
            lastError = "Update the model catalog first."
            return
        }

        isDownloadingModelPack = true
        modelDownloadProgress = 0
        lastError = nil
        defer { isDownloadingModelPack = false }

        do {
            for (index, model) in models.enumerated() {
                let temporaryURL = try await RemoteModelCatalogClient.download(model)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                _ = try await composition.localModelStorage.importModel(from: temporaryURL, name: model.name)
                modelDownloadProgress = Double(index + 1) / Double(models.count)
            }
            await refresh()
        } catch {
            lastError = "Test pack failed: \(error.localizedDescription)"
        }
    }

    func testProviderConnection() async {
        providerConnectionState = "Testing…"
        do {
            let models = try await composition.testProviderConnection()
            providerModels = models
            selectedProviderModelID = await composition.selectedProviderModelID()
            providerConnectionState = models.isEmpty ? "Failed: no models" : "Connected"
            lastError = nil
        } catch {
            providerConnectionState = "Connection failed"
            lastError = "Provider connection failed: \(error.localizedDescription)"
        }
    }

    func sendChat(_ message: String) async -> String? {
        chatPhase = "Received"
        do {
            chatPhase = "Preparing context"
            chatPhase = "Generating"
            let response = try await composition.chat(message)
            chatPhase = "Response ready"
            lastError = nil
            return response
        } catch {
            chatPhase = "Generation failed"
            lastError = "Agent chat failed: \(error.localizedDescription)"
            return nil
        }
    }

    func selectProviderRoute(_ route: ProviderRoute) async {
        await composition.selectProviderRoute(route)
        providerRoute = route
        providerConnectionState = "Not tested"
        lastError = nil
        await refresh()
    }

    func refreshProviderModels() async {
        providerModels = await composition.availableProviderModels()
        selectedProviderModelID = await composition.selectedProviderModelID()
    }

    func selectProviderModel(id: ModelID?) async {
        await composition.selectProviderModel(id: id)
        selectedProviderModelID = id
    }

    func configureProviderAPIKey(_ apiKey: String) async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Provider API key cannot be empty."
            return
        }
        do {
            try composition.secretStore.store(account: "openai-api-key", secret: Data(trimmed.utf8))
            lastError = nil
        } catch {
            lastError = "Could not save provider API key securely."
        }
        await refresh()
    }

    func removeProviderAPIKey() async {
        do {
            try composition.secretStore.delete(account: "openai-api-key")
            lastError = nil
            providerConnectionState = "Not configured"
        } catch {
            lastError = "Could not remove provider API key."
        }
        await refresh()
    }

    func hasProviderAPIKey() async -> Bool {
        do {
            guard let data = try composition.secretStore.load(account: "openai-api-key") else { return false }
            return !data.isEmpty
        } catch { return false }
    }

    func start() async { await run { try await composition.session.start() } }
    func pause() async { await run { try await composition.session.pause() } }
    func resume() async { await run { try await composition.session.resume() } }
    func stop() async { await run { try await composition.session.stop() } }

    func submitGoal(_ statement: String) async {
        lastSubmittedTask = statement
        executionProgress = nil
        executionTrace = []
        executionResult = nil
        await run {
            let goalID = try await composition.session.submitInput(statement)
            await refresh()
            _ = try await composition.orchestrator.run(goalID: goalID) { [weak self] progress in
                Task { @MainActor in
                    self?.executionProgress = progress
                    self?.executionTrace.append(progress)
                    if case .completed(let result) = progress { self?.executionResult = result }
                }
            }
        }
    }

    func retryTask() async {
        guard let statement = lastSubmittedTask else { return }
        await submitGoal(statement)
    }

    func resetTask() {
        lastSubmittedTask = nil
        executionProgress = nil
        executionTrace = []
        executionResult = nil
        lastError = nil
    }

    func importModel(from url: URL, name: String? = nil) async {
        await run { _ = try await composition.localModelStorage.importModel(from: url, name: name) }
    }

    func selectActiveModel(id: ModelID?) async {
        await run { try await composition.setActiveLocalModel(id: id) }
    }

    func loadActiveModel(options: LocalModelLoadingOptions? = nil) async {
        await run { _ = try await composition.loadActiveLocalModel(options: options) }
    }

    func unloadActiveModel() async {
        await run { try await composition.unloadActiveLocalModel() }
    }

    func deleteModel(id: ModelID) async {
        await run { try await composition.deleteLocalModel(id: id) }
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        await refresh()
    }
}
