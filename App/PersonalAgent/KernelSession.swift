import Foundation
import CryptoKit
import SwiftUI
import PAKernel
import PAComposition
import PAProviders
import PASkills
import PARuntime
import PASecurity
import PAWorkspace
import PATerminal

/// Reads user-controlled capability grants at decision time so changing Settings
/// takes effect without rebuilding the composition root.
struct UserConfiguredPolicyEvaluator: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        let defaults = UserDefaults.standard
        let capabilities: [(CapabilityLevel, String)] = [
            (.read, "permissions.capability.read"),
            (.write, "permissions.capability.write"),
            (.execute, "permissions.capability.execute"),
            (.network, "permissions.capability.network")
        ]
        for (capability, key) in capabilities where intent.capabilities.contains(capability) {
            let granted = defaults.object(forKey: key) == nil
                ? capability == .read
                : defaults.bool(forKey: key)
            guard granted else {
                return .deny("Permission disabled in Settings: \(key)")
            }
        }
        if intent.capabilities.contains(.destructive) {
            return .approve("Destructive action requires explicit confirmation")
        }
        return .allow("Granted by user Settings")
    }
}

struct SettingsTerminalCommandAuthorizer: TerminalCommandAuthorizing {
    private let policy = UserConfiguredPolicyEvaluator()

    func authorize(_ capabilities: Set<TerminalCapability>, summary: String) async -> Bool {
        await authorizationDecision(capabilities, summary: summary, confirmationGranted: false) == .allowed
    }

    func authorizationDecision(
        _ capabilities: Set<TerminalCapability>,
        summary: String,
        confirmationGranted: Bool
    ) async -> TerminalAuthorizationDecision {
        var required: CapabilityLevel = []
        if capabilities.contains(.read) { required.insert(.read) }
        if capabilities.contains(.write) { required.insert(.write) }
        if capabilities.contains(.execute) { required.insert(.execute) }
        if capabilities.contains(.network) { required.insert(.network) }
        if capabilities.contains(.destructive) { required.insert(.destructive) }
        let decision = await policy.evaluate(ActionIntent(capabilities: required, summary: summary))
        if decision.requiresApproval {
            guard capabilities.contains(.destructive) else { return .denied }
            return confirmationGranted ? .allowed : .requiresConfirmation
        }
        return decision.allowed ? .allowed : .denied
    }
}

/// Isolates high-frequency stream presentation from app-wide session observers.
/// Settings and other screens must not redraw for every streamed token batch.
@MainActor
final class ChatStreamPresentation: ObservableObject {
    @Published fileprivate(set) var streamingResponse = ""
    @Published fileprivate(set) var responseMetrics: ChatResponseMetrics?
}

@MainActor
final class KernelSession: ObservableObject {
    let composition: M8CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?
    @Published var providerID: String
    @Published var providerLifecycle: String
    @Published var moduleIDs: [String]
    @Published var skillManifests: [SkillManifest]
    @Published private(set) var agentManifests: [AgentManifest]
    @Published private(set) var selectedAgentID: String
    @Published private(set) var teamModeEnabled: Bool
    @Published private(set) var chatResponseLanguage: String
    @Published private(set) var chatContextTurnLimit: Int

    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelID: ModelID?
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineState: LocalModelLifecycleState
    @Published var isDownloadingDevModel = false
    @Published var executionProgress: AgentExecutionProgress?
    @Published var executionResult: String?
    @Published var presentedResult: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var chatHistory: [ChatTurn]
    @Published private(set) var conversations: [ChatConversation]
    @Published private(set) var currentConversationID: UUID
    @Published private(set) var memoryRecords: [MemorySnapshotItem]
    let chatStreamPresentation: ChatStreamPresentation
    private var generationStartedAt: Date?
    private var firstResponseDeltaAt: Date?
    private var executionTask: Task<Void, Never>?
    private var pendingStreamingDelta = ""
    private var streamingFlushScheduled = false
    private var streamingFlushGeneration = 0
    private let streamingFlushInterval: TimeInterval = 0.1

    /// Publish stream text at most 10 times per second to limit repeated SwiftUI layout work.
    /// All access is serialized on the main queue.
    private func enqueueStreamingDelta(_ delta: String) {
        if firstResponseDeltaAt == nil {
            firstResponseDeltaAt = Date()
        }
        pendingStreamingDelta += delta
        guard !streamingFlushScheduled else { return }
        streamingFlushScheduled = true
        let generation = streamingFlushGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + streamingFlushInterval) { [weak self] in
            guard let self, self.streamingFlushGeneration == generation else { return }
            self.streamingFlushScheduled = false
            guard !self.pendingStreamingDelta.isEmpty else { return }
            self.chatStreamPresentation.streamingResponse += self.pendingStreamingDelta
            self.pendingStreamingDelta = ""
            self.refreshResponseMetrics()
        }
    }

    private func discardPendingStreamingDelta() {
        pendingStreamingDelta = ""
        streamingFlushGeneration &+= 1
        streamingFlushScheduled = false
    }

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.chatStreamPresentation = ChatStreamPresentation()
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.moduleIDs = []
        self.skillManifests = []
        self.agentManifests = []
        self.selectedAgentID = UserDefaults.standard.string(forKey: "agent.selected.id") ?? "personal.default"
        self.teamModeEnabled = UserDefaults.standard.bool(forKey: "agent.team.mode")
        let savedResponseLanguage = UserDefaults.standard.string(forKey: "chat.response.language") ?? "auto"
        self.chatResponseLanguage = ["auto", "vi", "en"].contains(savedResponseLanguage) ? savedResponseLanguage : "auto"
        let savedContextTurnLimit = UserDefaults.standard.integer(forKey: "chat.context.turns")
        self.chatContextTurnLimit = [4, 8, 12, 24, 48].contains(savedContextTurnLimit) ? savedContextTurnLimit : 12
        self.installedModels = []
        self.activeModelID = nil
        self.activeModelDescriptor = nil
        self.activeEngineState = .unloaded
        self.presentedResult = nil
        let loaded = Self.loadConversations()
        self.conversations = loaded.conversations
        self.currentConversationID = loaded.currentID
        self.chatHistory = loaded.conversations.first(where: { $0.id == loaded.currentID })?.turns ?? []
        self.memoryRecords = []
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        await refreshMemory()
        providerLifecycle = await composition.currentProviderLifecycle()
        moduleIDs = await composition.registeredModuleIDs()
        do {
            skillManifests = try await composition.discoverSkills()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Optional startup discovery must not masquerade as a failed chat request.
            skillManifests = []
        }

        do {
            let discoveredAgents = try await composition.discoverAgents()
            agentManifests = discoveredAgents
            if !discoveredAgents.contains(where: { $0.id == selectedAgentID }) {
                selectedAgentID = discoveredAgents.first?.id ?? "personal.default"
                UserDefaults.standard.set(selectedAgentID, forKey: "agent.selected.id")
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Profile discovery may be temporarily unavailable while storage initializes.
            agentManifests = []
        }

        let storage = composition.localModelStorage
        do {
            installedModels = try await storage.listModels()
            activeModelID = try await storage.activeModelID()
            activeModelDescriptor = try await storage.activeModelDescriptor()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Inventory failures should not become chat-request banners. Engine load
            // failures remain visible in the following lifecycle-state check.
            installedModels = []
            activeModelID = nil
            activeModelDescriptor = nil
        }

        do {
            if let engine = try await composition.activeLocalModelEngine() {
                activeEngineState = await engine.lifecycleState
            } else {
                activeEngineState = .unloaded
            }
        } catch is CancellationError {
            activeEngineState = .unloaded
            return
        } catch let error as URLError where error.code == .cancelled {
            activeEngineState = .unloaded
            return
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

    /// Cancels the active request. The lifecycle manager observes task cancellation
    /// while consuming provider deltas and aborts the active goal when safe.
    func cancelCurrentGeneration() {
        guard isSubmitting else { return }
        executionTask?.cancel()
    }

    func submitGoal(_ statement: String) async {
        let normalizedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStatement.isEmpty else {
            lastError = "Enter a request before starting the Agent."
            return
        }
        guard !isSubmitting, executionTask == nil else {
            lastError = "Agent is still working. Wait for the current task to finish or stop it before starting another."
            await refresh()
            return
        }
        let conversationID = currentConversationID
        isSubmitting = true
        executionProgress = nil
        executionResult = nil
        presentedResult = nil
        chatStreamPresentation.streamingResponse = ""
        discardPendingStreamingDelta()
        chatStreamPresentation.responseMetrics = nil
        generationStartedAt = nil
        firstResponseDeltaAt = nil
        lastError = nil
        appendChatTurn(role: .user, content: normalizedStatement, conversationID: conversationID)
        let streamGeneration = streamingFlushGeneration
        let agentID = selectedAgentID
        let useTeamMode = teamModeEnabled
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let contextualInput: String
            do {
                try Task.checkCancellation()
                contextualInput = try await self.buildContextualInput(
                    for: normalizedStatement,
                    conversationID: conversationID
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                self.executionProgress = nil
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
                await self.refresh()
                return
            } catch {
                self.lastError = String(describing: error)
                await self.refresh()
                return
            }
            var goalID: GoalID?
            do {
                let lifecycle = self.state.lifecycle
                if lifecycle == .stopped {
                    try await self.composition.session.start()
                }
                if useTeamMode {
                    if let teamResult = try await self.composition.runChatTeamIfMatched(goalStatement: normalizedStatement) {
                        let result = teamResult.members.map { member in
                            "\(member.agentName) · \(member.skillResult.skillID.rawValue)\n\(Self.cleanSkillResult(member.skillResult.outputJSON))"
                        }.joined(separator: "\n\n")
                        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw KernelError.invalidStateUpdate("Agent team completed without a result")
                        }
                        self.executionResult = result
                        self.presentedResult = result
                        self.chatStreamPresentation.streamingResponse = ""
                        self.discardPendingStreamingDelta()
                        self.chatStreamPresentation.responseMetrics = nil
                        self.appendChatTurn(role: .assistant, content: result, conversationID: conversationID)
                        self.executionProgress = nil
                        await self.refresh()
                        return
                    }
                } else if let skillResult = try await self.composition.runChatSkillIfMatched(goalStatement: normalizedStatement, agentID: agentID) {
                    let result = Self.cleanSkillResult(skillResult.outputJSON)
                    guard !result.isEmpty else {
                        throw KernelError.invalidStateUpdate("Skill completed without a result")
                    }
                    self.executionResult = result
                    self.presentedResult = result
                    self.chatStreamPresentation.streamingResponse = ""
                    self.discardPendingStreamingDelta()
                    self.chatStreamPresentation.responseMetrics = nil
                    self.appendChatTurn(role: .assistant, content: result, conversationID: conversationID)
                    self.executionProgress = nil
                    await self.refresh()
                    return
                }

                goalID = try await self.composition.session.submitInput(contextualInput)
                await self.refresh()
                guard let goalID else {
                    throw KernelError.invalidStateUpdate("Runtime accepted input without a goal identifier")
                }
                self.executionProgress = .executing
                let evaluation = try await self.composition.lifecycleManager.run(
                    goalID: goalID,
                    rawInput: contextualInput,
                    onGenerationStarted: {
                        DispatchQueue.main.async { [weak self] in
                            self?.generationStartedAt = Date()
                        }
                    },
                    onReasoningDelta: { delta in
                        // Coalesce provider deltas before publishing SwiftUI state.
                        // Publishing per token invalidates every Settings view observing
                        // this session and can trigger an animated scroll per token.
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.streamingFlushGeneration == streamGeneration else { return }
                            self.enqueueStreamingDelta(delta)
                        }
                    }
                )
                let result = Self.cleanModelResult(evaluation.reason)
                guard !result.isEmpty else {
                    throw KernelError.invalidStateUpdate("Agent completed without a result")
                }
                self.executionResult = result
                self.presentedResult = result
                self.refreshResponseMetrics()
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
                self.appendChatTurn(role: .assistant, content: result, conversationID: conversationID)
                self.executionProgress = nil
            } catch is CancellationError {
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
            } catch let error as ProviderRuntimeError where error == .cancelled {
                // ProviderRuntime normalizes stream cancellation to its typed error.
                // Treat it as Stop, not a user-visible provider failure.
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
            } catch let error as URLError where error.code == .cancelled {
                // URLSession commonly reports task cancellation as URLError.cancelled,
                // not CancellationError. Treat both as an intentional Stop action.
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
            } catch {
                if let goalID,
                   let status = await self.composition.runtime.goal(id: goalID)?.status,
                   status == .active || status == .proposed {
                    try? await self.composition.runtime.abort(goalID: goalID)
                }
                self.executionProgress = nil
                self.chatStreamPresentation.streamingResponse = ""
                self.discardPendingStreamingDelta()
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
        isSubmitting = false
    }

    private func refreshResponseMetrics() {
        guard let generationStartedAt, !chatStreamPresentation.streamingResponse.isEmpty else { return }
        let elapsed = max(Date().timeIntervalSince(generationStartedAt), 0.001)
        let estimatedTokens = max(1, (chatStreamPresentation.streamingResponse.count + 3) / 4)
        let timeToFirstToken = firstResponseDeltaAt.map { max(0, $0.timeIntervalSince(generationStartedAt)) }
        chatStreamPresentation.responseMetrics = ChatResponseMetrics(
            timeToFirstToken: timeToFirstToken,
            elapsed: elapsed,
            estimatedOutputTokens: estimatedTokens,
            estimatedTokensPerSecond: Double(estimatedTokens) / elapsed
        )
    }

    func setChatResponseLanguage(_ language: String) {
        guard !isSubmitting, ["auto", "vi", "en"].contains(language) else { return }
        chatResponseLanguage = language
        UserDefaults.standard.set(language, forKey: "chat.response.language")
    }

    func setChatContextTurnLimit(_ limit: Int) {
        guard [4, 8, 12, 24, 48].contains(limit) else { return }
        chatContextTurnLimit = limit
        UserDefaults.standard.set(limit, forKey: "chat.context.turns")
    }

    func selectAgent(id: String) {
        guard !isSubmitting, agentManifests.contains(where: { $0.id == id }) else { return }
        selectedAgentID = id
        teamModeEnabled = false
        UserDefaults.standard.set(id, forKey: "agent.selected.id")
        UserDefaults.standard.set(false, forKey: "agent.team.mode")
    }

    func setTeamModeEnabled(_ enabled: Bool) {
        guard !isSubmitting else { return }
        teamModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "agent.team.mode")
    }

    func refreshMemory() async {
        do {
            memoryRecords = try await composition.memorySnapshot(limit: 50)
        } catch is CancellationError {
            // View/startup cancellation is expected and must not surface as an Agent error.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession cancellation is also an expected lifecycle event.
        } catch {
            lastError = String(describing: error)
        }
    }

    // Read-only Terminal bridges expose real runtime state without exposing secrets or
    // giving shell commands direct access to provider credentials.
    func terminalStatus() -> String {
        [
            "Agent: \(state.lifecycle.rawValue)",
            "Provider: \(providerID) [\(providerLifecycle)]",
            "Local model: \(activeModelID?.rawValue ?? "none")",
            "Installed models: \(installedModels.count)",
            "Skills: \(skillManifests.count)",
            "Memory records: \(memoryRecords.count)"
        ].joined(separator: "\n") + "\n"
    }

    func terminalProviderStatus() -> String {
        "Provider: \(providerID)\nLifecycle: \(providerLifecycle)\n"
    }

    func terminalModelStatus() -> String {
        "Active model: \(activeModelID?.rawValue ?? "none")\nInstalled models: \(installedModels.count)\n"
    }

    func terminalSkillsList(query: String = "") -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = skillManifests
            .filter {
                needle.isEmpty ||
                $0.id.rawValue.lowercased().contains(needle) ||
                $0.name.lowercased().contains(needle) ||
                $0.description.lowercased().contains(needle)
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        let rows = matches.map { "\($0.id.rawValue)\t\($0.name) — \($0.description)" }
        return rows.isEmpty ? "No skills found.\n" : rows.joined(separator: "\n") + "\n"
    }

    func terminalMemoryStatus() -> String {
        "Memory records loaded: \(memoryRecords.count)\n"
    }

    func terminalSyncStatus() -> String {
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: "github.sync.owner")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repository = defaults.string(forKey: "github.sync.repository")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch = defaults.string(forKey: "github.sync.branch")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !owner.isEmpty, !repository.isEmpty, !branch.isEmpty else {
            return "GitHub sync is not configured. Open Settings → GitHub repository sync.\n"
        }
        do {
            guard try KeychainSecretStore().load(account: "github.repository.token") != nil else {
                return "GitHub repository is configured, but its Keychain token is missing.\n"
            }
            return "GitHub sync configured: \(owner)/\(repository) @ \(branch). Token is stored in Keychain.\n"
        } catch {
            return "GitHub credential status unavailable; check Keychain access.\n"
        }
    }

    /// Shared sync entry point for Settings and Terminal. Always sync the same visible
    /// AgentOS workspace; never print or persist the GitHub token.
    func syncGitHubWorkspace(preview: Bool = false) async -> String {
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: "github.sync.owner")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repository = defaults.string(forKey: "github.sync.repository")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch = defaults.string(forKey: "github.sync.branch")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !owner.isEmpty, !repository.isEmpty, !branch.isEmpty else {
            return "Enter repository owner, repository name and branch in Settings.\n"
        }
        do {
            guard let tokenData = try KeychainSecretStore().load(account: "github.repository.token"),
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Save a GitHub token with repository Contents read/write permission first.\n"
            }
            let location = try GitHubRepositoryLocation(owner: owner, repository: repository, branch: branch)
            let workspace = try LocalAgentWorkspace.documents()
            try await workspace.prepare()
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            // Include the workspace identity so baselines from the legacy
            // Application Support root are never reused for the visible Documents root.
            let stateIdentity = "\(location.owner)/\(location.repository)@\(location.branch)#visible-documents"
            let stateName = Data(stateIdentity.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
            let stateURL = appSupport
                .appendingPathComponent("PersonalAgent/GitHubSync", isDirectory: true)
                .appendingPathComponent(stateName + ".json", isDirectory: false)
            let client = try GitHubRepositorySyncClient(
                location: location,
                stateURL: stateURL,
                tokenProvider: { token }
            )
            let result = try await client.synchronize(workspaceURL: workspace.rootURL, previewOnly: preview)
            func describe(_ paths: [String]) -> String {
                guard !paths.isEmpty else { return "none" }
                let shown = paths.prefix(20).joined(separator: ", ")
                return paths.count > 20 ? "\(shown), … (+\(paths.count - 20))" : shown
            }
            if preview {
                return "Sync preview only · no changes applied · upload: \(describe(result.uploadedPaths)) · download: \(describe(result.downloadedPaths)) · delete: \(describe(result.deletedPaths))\n"
            }
            return "Sync complete · \(result.commitSHA.prefix(7)) · upload \(result.uploadedPaths.count): \(describe(result.uploadedPaths)) · download \(result.downloadedPaths.count): \(describe(result.downloadedPaths)) · delete \(result.deletedPaths.count): \(describe(result.deletedPaths))\n"
        } catch GitHubRepositorySyncError.remoteConflict(let paths) {
            return "Sync conflict in: \(paths.joined(separator: ", ")). Resolve those files, then sync again.\n"
        } catch GitHubRepositorySyncError.remoteHeadChanged {
            return "The remote branch changed during sync. Fetch the latest state and sync again.\n"
        } catch GitHubRepositorySyncError.authenticationRequired {
            return "GitHub authentication required. Save a valid repository token.\n"
        } catch {
            return "Sync failed safely: \(error.localizedDescription)\n"
        }
    }

    func runFromTerminal(_ statement: String) async -> String {
        guard !isSubmitting else { return "Agent is busy; wait for the current task to finish.\n" }
        await submitGoal(statement)
        if let result = presentedResult, !result.isEmpty { return result + "\n" }
        if let error = lastError, !error.isEmpty { return "Agent error: \(error)\n" }
        return "Agent finished without a response.\n"
    }

    func remember(_ content: String, kind: String = "fact") async {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        await run {
            try await composition.remember(value, kind: kind)
        }
        await refreshMemory()
    }

    func clearMemory() async {
        let cleared = await run {
            try await composition.clearMemory()
        }
        // run(_:) refreshes the snapshot even on failure. Never hide persisted
        // records unless the underlying delete operation actually succeeded.
        if cleared {
            memoryRecords = []
        }
    }

    func forgetMemory(id: String, reason: String = "user-requested") async {
        await run {
            try await composition.memoryRuntime.forget(
                id: MemoryRecordID(rawValue: id),
                reason: reason
            )
        }
        await refreshMemory()
    }

    func downloadDevModel() async {
        guard !isDownloadingDevModel else { return }
        isDownloadingDevModel = true
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

            // URLSession download URLs are temporary implementation files and may not end in .gguf.
            // Stage the verified bytes under a .gguf filename before passing them through strict storage validation.
            let stagedModelURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("download-\(UUID().uuidString)")
                .appendingPathExtension("gguf")
            try FileManager.default.moveItem(at: temporaryURL, to: stagedModelURL)
            defer { try? FileManager.default.removeItem(at: stagedModelURL) }

            _ = try await composition.localModelStorage.importModel(
                from: stagedModelURL,
                name: "Qwen2.5-0.5B-Instruct Q4_K_M (Dev)"
            )
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

            // Storage owns security-scoped access and copies directly into its managed directory.
            // Avoid a second full-size temporary copy, which can exhaust device storage.
            _ = try await composition.localModelStorage.importModel(
                from: url,
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
            if activeModelID == id,
               case .loaded = activeEngineState {
                try await composition.unloadActiveLocalModel()
            }
            try await composition.deleteLocalModel(id: id)
        }
    }

    private func appendChatTurn(role: ChatTurn.Role, content: String, conversationID: UUID? = nil) {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = conversationID ?? currentConversationID
        guard !value.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == targetID }) else { return }

        var conversation = conversations[index]
        conversation.turns.append(ChatTurn(role: role, content: value))
        if conversation.turns.count > 100 {
            conversation.turns.removeFirst(conversation.turns.count - 100)
        }
        if conversation.title == "New conversation", role == .user {
            conversation.title = String(value.prefix(40))
        }
        conversation.updatedAt = Date()
        conversations[index] = conversation
        if targetID == currentConversationID {
            chatHistory = conversation.turns
        }
        persistConversations()
    }

    func setChatPersistence(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "privacy.persistChat")
        guard !enabled else {
            persistConversations()
            return
        }

        let conversation = ChatConversation(title: "New conversation")
        conversations = [conversation]
        currentConversationID = conversation.id
        chatHistory = []
        executionResult = nil
        presentedResult = nil
        UserDefaults.standard.removeObject(forKey: "chat.conversations.v1")
        UserDefaults.standard.removeObject(forKey: "chat.history.v1")
        UserDefaults.standard.removeObject(forKey: "chat.currentConversation.v1")
    }

    func newConversation() {
        guard !isSubmitting else { return }
        let conversation = ChatConversation(title: "New conversation")
        conversations.insert(conversation, at: 0)
        currentConversationID = conversation.id
        chatHistory = []
        UserDefaults.standard.set(conversation.id.uuidString, forKey: "chat.currentConversation.v1")
        persistConversations()
    }

    var canRegenerateLastResponse: Bool {
        guard !isSubmitting, executionTask == nil,
              let conversation = conversations.first(where: { $0.id == currentConversationID }),
              conversation.turns.count >= 2 else { return false }
        return conversation.turns[conversation.turns.count - 1].role == .assistant
            && conversation.turns[conversation.turns.count - 2].role == .user
    }

    /// Re-runs the most recent user request without duplicating it in visible history.
    func regenerateLastResponse() async {
        guard canRegenerateLastResponse,
              let index = conversations.firstIndex(where: { $0.id == currentConversationID }) else { return }
        let prompt = conversations[index].turns[conversations[index].turns.count - 2].content
        conversations[index].turns.removeLast(2)
        conversations[index].updatedAt = Date()
        chatHistory = conversations[index].turns
        persistConversations()
        await submitGoal(prompt)
    }
    func selectConversation(id: UUID) {
        guard !isSubmitting, let conversation = conversations.first(where: { $0.id == id }) else { return }
        currentConversationID = id
        chatHistory = conversation.turns
        UserDefaults.standard.set(id.uuidString, forKey: "chat.currentConversation.v1")
    }

    func renameCurrentConversation(_ title: String) {
        guard !isSubmitting else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == currentConversationID }) else { return }
        conversations[index].title = String(value.prefix(60))
        conversations[index].updatedAt = Date()
        persistConversations()
    }

    func deleteConversation(id: UUID) {
        guard !isSubmitting else { return }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            let conversation = ChatConversation(title: "New conversation")
            conversations = [conversation]
            currentConversationID = conversation.id
            chatHistory = []
        } else if !conversations.contains(where: { $0.id == currentConversationID }) {
            currentConversationID = conversations[0].id
            chatHistory = conversations[0].turns
        }
        UserDefaults.standard.set(currentConversationID.uuidString, forKey: "chat.currentConversation.v1")
        persistConversations()
    }

    private func buildContextualInput(for statement: String, conversationID: UUID) async throws -> String {
        let storedContextTurns = UserDefaults.standard.integer(forKey: "chat.context.turns")
        let contextTurns = [4, 8, 12, 24, 48].contains(storedContextTurns) ? storedContextTurns : 12
        if chatContextTurnLimit != contextTurns {
            chatContextTurnLimit = contextTurns
        }
        let conversationTurns = conversations.first(where: { $0.id == conversationID })?.turns ?? []
        let priorTurns = (conversationTurns.last?.role == .user && conversationTurns.last?.content == statement)
            ? conversationTurns.dropLast()
            : conversationTurns[...]
        let recent = priorTurns.suffix(contextTurns)
        let memory = try await composition.memoryContext(for: statement)
        var sections: [String] = []
        if !recent.isEmpty {
            let transcript = recent.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
            sections.append("Conversation context:\n\(transcript)")
        }
        if !memory.isEmpty {
            sections.append("Relevant memory:\n" + memory.joined(separator: "\n"))
        }
        switch chatResponseLanguage {
        case "vi":
            sections.append("Response preference: Reply in natural, fluent Vietnamese unless the user explicitly asks for another language.")
        case "en":
            sections.append("Response preference: Reply in clear, natural English unless the user explicitly asks for another language.")
        default:
            break
        }
        sections.append("Current user request:\n\(statement)")
        return sections.joined(separator: "\n\n")
    }

    private static func loadConversations() -> (conversations: [ChatConversation], currentID: UUID) {
        if UserDefaults.standard.object(forKey: "privacy.persistChat") as? Bool == false {
            let conversation = ChatConversation(title: "New conversation")
            return ([conversation], conversation.id)
        }
        if let data = UserDefaults.standard.data(forKey: "chat.conversations.v1"),
           let stored = try? JSONDecoder().decode([ChatConversation].self, from: data),
           !stored.isEmpty {
            let storedCurrentID = UserDefaults.standard.string(forKey: "chat.currentConversation.v1")
                .flatMap(UUID.init(uuidString:))
            let currentID = storedCurrentID.flatMap { id in
                stored.contains(where: { $0.id == id }) ? id : nil
            } ?? stored[0].id
            return (stored, currentID)
        }
        if let data = UserDefaults.standard.data(forKey: "chat.history.v1"),
           let history = try? JSONDecoder().decode([ChatTurn].self, from: data),
           !history.isEmpty {
            let migrated = ChatConversation(title: "Conversation", turns: history)
            return ([migrated], migrated.id)
        }
        let conversation = ChatConversation(title: "New conversation")
        return ([conversation], conversation.id)
    }

    private func persistConversations() {
        guard UserDefaults.standard.object(forKey: "privacy.persistChat") as? Bool != false else {
            UserDefaults.standard.removeObject(forKey: "chat.conversations.v1")
            UserDefaults.standard.removeObject(forKey: "chat.history.v1")
            UserDefaults.standard.removeObject(forKey: "chat.currentConversation.v1")
            return
        }
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: "chat.conversations.v1")
        UserDefaults.standard.removeObject(forKey: "chat.history.v1")
    }

    private static func cleanSkillResult(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            return cleanModelResult(raw)
        }
        return cleanModelResult(text)
    }

    private static func sanitizeModelOutput(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanModelResult(_ raw: String) -> String {
        var result = sanitizeModelOutput(raw)

        // Strip complete control tokens and common truncated variants from GGUF output.
        for token in ["<|im_end|>", "||im_end|>", "|im_end|>", "<|im_start|>", "||im_start|>", "<|endoftext|>", "||endoftext|>", "<|eot_id|>", "||eot_id|>", "<|assistant|>", "<|user|>"] {
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

    @discardableResult
    private func run(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            lastError = nil
            await refresh()
            return true
        } catch let error as KernelError {
            switch error {
            case .runtimeNotExecutable(.stopped):
                lastError = "Agent runtime is stopped. Start the Agent runtime before submitting another task."
            default:
                lastError = error.description
            }
        } catch is CancellationError {
            // Cancellation is not success; keep the refreshed persisted state.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession cancellation during startup/model preparation is expected.
        } catch let error as ProviderRuntimeError where error == .cancelled {
            // Providers may normalize cancellation into their typed runtime error.
        } catch {
            lastError = String(describing: error)
        }
        await refresh()
        return false
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

struct ChatConversation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var turns: [ChatTurn]
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, turns: [ChatTurn] = [], updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.turns = turns
        self.updatedAt = updatedAt
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

struct ChatResponseMetrics: Equatable, Sendable {
    let timeToFirstToken: TimeInterval?
    let elapsed: TimeInterval
    let estimatedOutputTokens: Int
    let estimatedTokensPerSecond: Double
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
