import Foundation
import CryptoKit
import SwiftUI
import PAKernel
import PAComposition
import PAProviders
import PARuntime

@MainActor
final class KernelSession: ObservableObject {
    let composition: M8CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?
    @Published var providerID: String
    @Published var providerLifecycle: String
    @Published var moduleIDs: [String]

    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelID: ModelID?
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineState: LocalModelLifecycleState
    @Published var isDownloadingDevModel = false
    @Published var devModelDownloadProgress: Double = 0
    @Published var executionProgress: AgentExecutionProgress?
    @Published var executionResult: String?
    @Published var presentedResult: String?
    @Published private(set) var chatHistory: [ChatTurn]
    private var executionTask: Task<Void, Never>?

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.moduleIDs = []
        self.installedModels = []
        self.activeModelID = nil
        self.activeModelDescriptor = nil
        self.activeEngineState = .unloaded
        self.presentedResult = nil
        self.chatHistory = Self.loadChatHistory()
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
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

    /// Startup-only residency preparation. Refresh remains observational and side-effect free.
    func prepareActiveModel() async {
        guard activeModelID != nil else { return }
        await run { _ = try await composition.loadActiveLocalModel() }
    }

    func start() async { await run { try await composition.session.start() } }
    func pause() async { await run { try await composition.session.pause() } }
    func resume() async { await run { try await composition.session.resume() } }
    func stop() async {
        let task = executionTask
        task?.cancel()
        await run { try await composition.session.stop() }
        if let task {
            await task.value
        }
        executionTask = nil
    }

    func submitGoal(_ statement: String) async {
        guard executionTask == nil else {
            lastError = "Agent is still working. Wait for the current task to finish or stop it before starting another."
            await refresh()
            return
        }
        executionProgress = nil
        executionResult = nil
        presentedResult = nil
        lastError = nil
        appendChatTurn(role: .user, content: statement)
        let contextualInput = buildContextualInput(for: statement)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var goalID: GoalID?
            do {
                let lifecycle = self.state.lifecycle
                if lifecycle == .stopped {
                    try await self.composition.session.start()
                }
                goalID = try await self.composition.session.submitInput(contextualInput)
                await self.refresh()
                guard let goalID else {
                    throw KernelError.invalidStateUpdate("Runtime accepted input without a goal identifier")
                }
                self.executionProgress = .executing
                let evaluation = try await self.composition.lifecycleManager.run(
                    goalID: goalID,
                    rawInput: contextualInput
                )
                let result = Self.cleanModelResult(evaluation.reason)
                guard !result.isEmpty else {
                    throw KernelError.invalidStateUpdate("Agent completed without a result")
                }
                self.executionResult = result
                self.presentedResult = result
                self.appendChatTurn(role: .assistant, content: result)
                self.executionProgress = nil
            } catch is CancellationError {
                // Cancellation is not success. Clear the active goal so Stop cannot
                // strand it and block the next Start/submit cycle.
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
            } catch {
                // Provider/model failure must not strand an active goal and block the next turn.
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
                if let kernelError = error as? KernelError {
                    self.lastError = kernelError.description
                } else {
                    self.lastError = String(describing: error)
                }
            }
            await self.refresh()
        }
        executionTask = task
        await task.value
        executionTask = nil
    }

    func downloadDevModel() async {
        guard !isDownloadingDevModel else { return }
        isDownloadingDevModel = true
        devModelDownloadProgress = 0
        lastError = nil
        defer { isDownloadingDevModel = false }

        let urlString = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf?download=true"
        let expectedSHA256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
        let maximumBytes: Int64 = 600 * 1024 * 1024

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
                name: "Qwen2.5-0.5B-Instruct Q4_K_M (Dev)"
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
            guard url.pathExtension.lowercased() == "gguf" else {
                throw KernelError.invalidStateUpdate("Only GGUF model files can be imported.")
            }

            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Files/iCloud providers can invalidate the external URL after the
            // picker/open-document callback returns. Copy while the security
            // scope is alive, then let LocalModelStorage consume a stable local URL.
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString)")
                .appendingPathExtension("gguf")
            try FileManager.default.copyItem(at: url, to: temporaryURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            _ = try await composition.localModelStorage.importModel(
                from: temporaryURL,
                name: name
            )
            await refresh()
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

    private func appendChatTurn(role: ChatTurn.Role, content: String) {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        chatHistory.append(ChatTurn(role: role, content: value))
        if chatHistory.count > 100 { chatHistory.removeFirst(chatHistory.count - 100) }
        if let data = try? JSONEncoder().encode(chatHistory) {
            UserDefaults.standard.set(data, forKey: "chat.history.v1")
        }
    }

    private func buildContextualInput(for statement: String) -> String {
        let recent = chatHistory.suffix(12)
        guard !recent.isEmpty else { return statement }
        let transcript = recent.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        return "Conversation context:\n\(transcript)\n\nCurrent user request:\n\(statement)"
    }

    private static func loadChatHistory() -> [ChatTurn] {
        guard let data = UserDefaults.standard.data(forKey: "chat.history.v1"),
              let history = try? JSONDecoder().decode([ChatTurn].self, from: data) else { return [] }
        return history
    }

    private static func cleanModelResult(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Qwen and other chat templates may leak control tokens into the
        // final UI result. They are transport markers, not user-facing text.
        for token in ["<|im_end|>", "<|im_start|>", "<|endoftext|>", "<|eot_id|>", "<|assistant|>", "<|user|>"] {
            result = result.replacingOccurrences(of: token, with: "")
        }

        if result.hasPrefix("Kết quả:") {
            result.removeFirst("Kết quả:".count)
        } else if result.hasPrefix("Kết quả") {
            result.removeFirst("Kết quả".count)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
        } catch let error as KernelError {
            switch error {
            case .runtimeNotExecutable(.stopped):
                lastError = "Agent runtime is stopped. Start the Agent runtime before submitting another task."
            default:
                lastError = error.description
            }
        } catch is CancellationError {
            // Stop intentionally cancels an active execution; lifecycle state is authoritative.
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
            return "Dev model download failed with HTTP \(status)."
        case .invalidSize(let size):
            return "Dev model size is invalid: \(size) bytes."
        case .checksumMismatch(let expected, let actual):
            return "Dev model SHA-256 mismatch. Expected \(expected), got \(actual)."
        }
    }
}

struct ChatTurn: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let content: String
    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id; self.role = role; self.content = content
    }
}
