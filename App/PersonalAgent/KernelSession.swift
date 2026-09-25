import Foundation
import CryptoKit
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
    @Published var providerLifecycle: String
    @Published var providerConnectionState: String
    @Published var providerModels: [ModelIdentity]
    @Published var selectedProviderModelID: ModelID?
    @Published var moduleIDs: [String]

    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelID: ModelID?
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineState: LocalModelLifecycleState
    @Published var isDownloadingDevModel = false
    @Published var devModelDownloadProgress: Double = 0
    @Published var executionProgress: AgentExecutionProgress?
    @Published var executionTrace: [AgentExecutionProgress] = []
    @Published var executionResult: String?
    private var lastSubmittedTask: String?

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.providerConnectionState = "Not tested"
        self.providerModels = []
        self.selectedProviderModelID = nil
        self.moduleIDs = []
        self.installedModels = []
        self.activeModelID = nil
        self.activeModelDescriptor = nil
        self.activeEngineState = .unloaded
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
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
            lastError = "Provider connection failed: \\(error.localizedDescription)"
        }
    }

    func sendChat(_ message: String) async -> String? {
        do {
            let response = try await composition.chat(message)
            lastError = nil
            return response
        } catch {
            lastError = "Agent chat failed: \\(error.localizedDescription)"
            return nil
        }
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
            try composition.secretStore.store(
                account: "openai-api-key",
                secret: Data(trimmed.utf8)
            )
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
        } catch {
            return false
        }
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
                    if case .completed(let result) = progress {
                        self?.executionResult = result
                    }
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

    func downloadDevModel() async {
        guard !isDownloadingDevModel else { return }
        isDownloadingDevModel = true
        devModelDownloadProgress = 0
        lastError = nil
        defer { isDownloadingDevModel = false }

        let urlString = "https://huggingface.co/ggml-org/SmolLM2-135M-GGUF/resolve/main/SmolLM2-135M-BF16.gguf?download=true"
        let expectedSHA256 = "9d00c56fe60a70659db0d905dfec6b95ea52b8d5f3f8c9b1229448b04402e6bf"
        let maximumBytes: Int64 = 350 * 1024 * 1024

        do {
            guard let remoteURL = URL(string: urlString) else { throw DevModelDownloadError.invalidURL }
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DevModelDownloadError.httpStatus(http.statusCode)
            }

            let size = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int64 ?? 0
            guard size > 0, size <= maximumBytes else {
                throw DevModelDownloadError.invalidSize(size)
            }

            let digest = try Self.sha256(of: temporaryURL)
            guard digest == expectedSHA256 else {
                throw DevModelDownloadError.checksumMismatch(expected: expectedSHA256, actual: digest)
            }

            _ = try await composition.localModelStorage.importModel(
                from: temporaryURL,
                name: "SmolLM2-135M (Dev)"
            )
            try? FileManager.default.removeItem(at: temporaryURL)
            devModelDownloadProgress = 1
            await refresh()
        } catch {
            lastError = String(describing: error)
        }
    }

    func importModel(from url: URL, name: String? = nil) async {
        await run {
            _ = try await composition.localModelStorage.importModel(from: url, name: name)
        }
    }

    func selectActiveModel(id: ModelID?) async {
        await run {
            try await composition.setActiveLocalModel(id: id)
        }
    }

    func loadActiveModel(options: LocalModelLoadingOptions? = nil) async {
        await run {
            _ = try await composition.loadActiveLocalModel(options: options)
        }
    }

    func unloadActiveModel() async {
        await run {
            try await composition.unloadActiveLocalModel()
        }
    }

    func deleteModel(id: ModelID) async {
        await run {
            try await composition.deleteLocalModel(id: id)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

private enum DevModelDownloadError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case invalidSize(Int64)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Dev model URL is invalid."
        case .httpStatus(let status):
            return "Dev model download failed with HTTP (status)."
        case .invalidSize(let size):
            return "Dev model size is invalid: (size) bytes."
        case .checksumMismatch(let expected, let actual):
            return "Dev model SHA-256 mismatch. Expected (expected), got (actual)."
        }
    }
}
