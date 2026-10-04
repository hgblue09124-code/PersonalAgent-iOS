import Foundation
import PAKernel
import PAProviders
import PAProvidersLocal
import PAStorageModels
import PAMemory
import PAStorageMemory
import PAModules
import PARuntime
import PAEvents
import PAObservability
import PATools
import PASkills
import PASecurity

/// Manages active local model engine instance lifetime and residency in product composition.
public actor LocalModelRuntimeCoordinator: Sendable {
    private let storage: any LocalModelStorage
    private let deviceCapabilityProvider: any DeviceCapabilityProviding
    private var cachedEngine: (any LocalModelEngine)?

    private let engineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)?

    public init(
        storage: any LocalModelStorage,
        deviceCapabilityProvider: any DeviceCapabilityProviding,
        engineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)? = nil
    ) {
        self.storage = storage
        self.deviceCapabilityProvider = deviceCapabilityProvider
        self.engineFactory = engineFactory
    }

    private func ensureCachedEngineUnloaded() async throws {
        guard let existing = cachedEngine else { return }
        try await existing.unload()
        cachedEngine = nil
    }

    public func activeLocalModelEngine() async throws -> (any LocalModelEngine)? {
        guard let activeID = try await storage.activeModelID() else {
            try await ensureCachedEngineUnloaded()
            return nil
        }

        guard let descriptor = try await storage.activeModelDescriptor(),
              descriptor.id == activeID,
              let fileURL = try await storage.modelFileURL(for: activeID) else {
            try await ensureCachedEngineUnloaded()
            throw LocalModelStorageError.modelNotFound(activeID)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try await ensureCachedEngineUnloaded()
            throw LocalModelStorageError.fileNotFound(fileURL)
        }

        if let existing = cachedEngine, existing.identity.id == activeID {
            return existing
        }

        try await ensureCachedEngineUnloaded()

        let identity = LocalModelIdentity(
            id: descriptor.id,
            name: descriptor.name,
            parameterCount: descriptor.parameterCount,
            quantization: descriptor.quantization,
            contextTokenLimit: descriptor.contextWindow ?? 8192,
            fileSizeBytes: descriptor.fileSizeBytes,
            localURL: fileURL
        )

        let newEngine: any LocalModelEngine
        if let factory = engineFactory {
            newEngine = factory(identity, deviceCapabilityProvider)
        } else {
            newEngine = LlamaCPPModelEngine(
                identity: identity,
                deviceCapabilityProvider: deviceCapabilityProvider
            )
        }
        cachedEngine = newEngine
        return newEngine
    }

    public func loadActiveModel(options: LocalModelLoadingOptions? = nil) async throws -> any LocalModelEngine {
        guard let engine = try await activeLocalModelEngine() else {
            throw LlamaCPPEngineError.modelNotLoaded
        }

        let opts = options ?? LocalModelLoadingOptions()
        while true {
            switch await engine.lifecycleState {
            case .loaded:
                return engine
            case .loading:
                try await Task.sleep(for: .milliseconds(50))
            case .unloaded, .failed:
                try await engine.load(options: opts)
                return engine
            case .unloading:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    public func unloadActiveModel() async throws {
        try await ensureCachedEngineUnloaded()
    }

    public func setActiveModel(id: ModelID?) async throws {
        let currentActiveID = try await storage.activeModelID()
        guard currentActiveID != id else { return }

        let previousEngine = cachedEngine

        try await ensureCachedEngineUnloaded()

        do {
            try await storage.setActiveModel(id: id)
        } catch {
            try? await storage.setActiveModel(id: currentActiveID)
            self.cachedEngine = previousEngine
            throw error
        }
    }

    public func deleteModel(id: ModelID) async throws {
        if let engine = cachedEngine, engine.identity.id == id {
            try await ensureCachedEngineUnloaded()
        }
        try await storage.deleteModel(id: id)
    }
}

/// Production-safe fallback used when Composition is created without an injected provider.
/// It preserves the existing deterministic default behavior without depending on test targets.
private struct DefaultCompositionProvider: LLMProvider {
    let identity = ProviderIdentity(
        id: ProviderID(rawValue: "default"),
        displayName: "Default Composition Provider",
        models: [ModelIdentity(id: ModelID(rawValue: "default-text"), displayName: "Default Text", contextTokenLimit: 8192)]
    )
    let capabilities: ProviderCapabilities = [.textGeneration, .streaming]

    var health: ProviderHealth {
        get async { .healthy }
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try Task.checkCancellation()
        return LLMResponse(text: "ok", finishReason: "stop", model: ModelID(rawValue: "default-text"))
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.delta("ok"))
            continuation.yield(.completed(LLMResponse(text: "ok", finishReason: "stop", model: ModelID(rawValue: "default-text"))))
            continuation.finish()
        }
    }
}

/// Dynamic provider wrapper routing completion/streaming requests to the active local model engine when configured,
/// propagating local resolution/execution errors fail-closed, and falling back to the configured default provider
/// strictly when no local model is configured.
public final class DynamicActiveProvider: LLMProvider, @unchecked Sendable {
    private let fallbackProvider: any LLMProvider
    private let coordinator: LocalModelRuntimeCoordinator

    public init(
        fallbackProvider: any LLMProvider,
        coordinator: LocalModelRuntimeCoordinator
    ) {
        self.fallbackProvider = fallbackProvider
        self.coordinator = coordinator
    }

    private enum ActiveResolution {
        case noActiveModel
        case activeModel(any LLMProvider)
    }

    private func resolveActiveProvider() async throws -> ActiveResolution {
        guard let engine = try await coordinator.activeLocalModelEngine() else {
            return .noActiveModel
        }
        return .activeModel(LocalModelProviderAdapter(engine: engine))
    }

    public var identity: ProviderIdentity {
        fallbackProvider.identity
    }

    public var capabilities: ProviderCapabilities {
        [.textGeneration, .streaming, .localInference]
    }

    public var health: ProviderHealth {
        get async {
            do {
                switch try await resolveActiveProvider() {
                case .noActiveModel:
                    return await fallbackProvider.health
                case .activeModel(let adapter):
                    return await adapter.health
                }
            } catch {
                return .unavailable
            }
        }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        switch try await resolveActiveProvider() {
        case .noActiveModel:
            return try await fallbackProvider.complete(request)
        case .activeModel:
            let engine = try await coordinator.loadActiveModel()
            return try await LocalModelProviderAdapter(engine: engine).complete(request)
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let fallback = fallbackProvider
        let coord = coordinator
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let engine = try await coord.activeLocalModelEngine() else {
                        for try await event in fallback.stream(request) {
                            try Task.checkCancellation()
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    }
                    let loadedEngine = try await coord.loadActiveModel()
                    let adapter = LocalModelProviderAdapter(engine: loadedEngine)
                    for try await event in adapter.stream(request) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}


private struct ConfiguredRemoteProvider: LLMProvider, Sendable {
    private let fallback: any LLMProvider

    init(fallback: any LLMProvider) {
        self.fallback = fallback
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "provider.remote.enabled")
    }

    private var selectedID: String {
        UserDefaults.standard.string(forKey: "provider.remote.id") ?? "openai"
    }

    private var keychainAccount: String { "provider.api-key.\(selectedID)" }

    var identity: ProviderIdentity {
        switch selectedID {
        case "grok":
            return ProviderIdentity(
                id: ProviderID(rawValue: "grok"),
                displayName: "Grok",
                models: [ModelIdentity(id: ModelID(rawValue: "grok-3"), displayName: "Grok 3", contextTokenLimit: 131_072)]
            )
        default:
            return ProviderIdentity(
                id: ProviderID(rawValue: "openai"),
                displayName: "OpenAI",
                models: [ModelIdentity(id: ModelID(rawValue: "gpt-4o-mini"), displayName: "GPT-4o mini", contextTokenLimit: 128_000)]
            )
        }
    }

    var capabilities: ProviderCapabilities { [.textGeneration, .streaming] }

    var health: ProviderHealth {
        get async {
            guard enabled else { return await fallback.health }
            return (try? credential()) == nil ? .unavailable : .unknown
        }
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard enabled else { return try await fallback.complete(request) }
        let token = try credential()
        let endpoint: String
        let model: String
        switch selectedID {
        case "grok":
            endpoint = "https://api.x.ai/v1/chat/completions"
            model = request.model.rawValue.isEmpty ? "grok-3" : request.model.rawValue
        default:
            endpoint = "https://api.openai.com/v1/chat/completions"
            model = request.model.rawValue.isEmpty ? "gpt-4o-mini" : request.model.rawValue
        }

        let messages = request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false
        ]
        if let temperature = request.parameters.temperature { body["temperature"] = temperature }
        if let maxTokens = request.parameters.maxOutputTokens { body["max_tokens"] = maxTokens }
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await URLSessionNetworkAccess().data(for: NetworkRequest(
            url: endpoint,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: data
        ))
        guard response.statusCode == 200 else {
            throw ProviderRuntimeError.from(statusCode: response.statusCode)
        }
        let root = try JSONDecoder().decode(ChatResponseEnvelope.self, from: response.body)
        guard let text = root.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ProviderRuntimeError.decodingFailure
        }
        return LLMResponse(text: text, finishReason: root.choices.first?.finishReason ?? "stop", model: ModelID(rawValue: model))
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request)
                    try Task.checkCancellation()
                    continuation.yield(.delta(response.text))
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderRuntimeError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func credential() throws -> String {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PersonalAgent.Provider",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderRuntimeError.authenticationFailure
        }
        return token
        #else
        throw ProviderRuntimeError.authenticationFailure
        #endif
    }
}

private struct ChatResponseEnvelope: Decodable, Sendable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable, Sendable {
    let message: ChatMessageEnvelope
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct ChatMessageEnvelope: Decodable, Sendable {
    let content: String?
}

public struct M8CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let eventLog: any EventLog
    public let idempotentEventLog: IdempotentEventLog
    public let runtime: AgentRuntime
    public let session: AgentSession
    public let persistenceContainer: ProductPersistenceContainer
    public let localModelStorage: any LocalModelStorage
    public let deviceCapabilityProvider: any DeviceCapabilityProviding
    public let localModelRuntimeCoordinator: LocalModelRuntimeCoordinator
    public let providerRuntime: ProviderRuntime?
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime
    public let skillRuntime: SkillRuntime
    public let memoryStore: any MemoryStore
    public let memoryRuntime: MemoryRuntime
    public let orchestrator: M6Orchestrator
    public let runStore: any RunStore
    public let attemptStore: any ExecutionAttemptStore
    public let checkpointStore: any RunCheckpointStore
    public let journalStore: any StateJournalStore
    public let executionBoundary: ExecutionBoundary
    public let lifecycleManager: RunLifecycleManager
    public let recoveryEngine: RunRecoveryEngine

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal M8 Agent"),
        logger: any AgentLogger = NullLoggerBridge(),
        eventLog: (any EventLog)? = nil,
        provider: (any LLMProvider)? = nil,
        memoryStore: (any MemoryStore)? = nil,
        storeDirectoryURL: URL? = nil,
        localModelStorage: (any LocalModelStorage)? = nil,
        deviceCapabilityProvider: (any DeviceCapabilityProviding)? = nil,
        localModelEngineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)? = nil,
        policy: (any PolicyEvaluating)? = nil,
        approvalGate: (any ApprovalGate)? = nil,
        evidenceResolver: (any ExecutionEvidenceResolver)? = nil,
        targetCapabilities: [ExecutionTargetCapability] = [],
        modules: [any Module] = [],
        tools: [any Tool] = [],
        runStore: (any RunStore)? = nil,
        attemptStore: (any ExecutionAttemptStore)? = nil,
        checkpointStore: (any RunCheckpointStore)? = nil,
        journalStore: (any StateJournalStore)? = nil,
        mutationEvidenceStore: (any MutationEvidenceStore)? = nil
    ) async throws {
        let rootDirectoryURL: URL
        if let storeDirectoryURL {
            rootDirectoryURL = storeDirectoryURL
        } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            rootDirectoryURL = appSupport.appendingPathComponent("PersonalAgent/M8Product")
        } else {
            rootDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalAgent/M8Product")
        }

        let persistenceContainer = try ProductPersistenceContainer(baseDirectoryURL: rootDirectoryURL)
        self.persistenceContainer = persistenceContainer

        let resolvedStorage: any LocalModelStorage
        if let localModelStorage {
            resolvedStorage = localModelStorage
        } else {
            let modelsDir = persistenceContainer.modelMetadataDirectoryURL.appendingPathComponent("Models")
            resolvedStorage = try FileBackedLocalModelStorage(modelsDirectoryURL: modelsDir)
        }
        self.localModelStorage = resolvedStorage

        let resolvedDeviceCapability = deviceCapabilityProvider ?? DefaultDeviceCapabilityProvider()
        self.deviceCapabilityProvider = resolvedDeviceCapability

        let coordinator = LocalModelRuntimeCoordinator(
            storage: resolvedStorage,
            deviceCapabilityProvider: resolvedDeviceCapability,
            engineFactory: localModelEngineFactory
        )
        self.localModelRuntimeCoordinator = coordinator

        let rawLog: any EventLog
        if let eventLog {
            rawLog = eventLog
        } else {
            rawLog = try FileBackedEventLog(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        }

        let idempotentLog = IdempotentEventLog(innerLog: rawLog)
        self.milestone = .m8
        self.logger = logger
        self.eventLog = idempotentLog
        self.idempotentEventLog = idempotentLog

        let fallbackProvider = ConfiguredRemoteProvider(fallback: provider ?? DefaultCompositionProvider())
        let dynamicProvider = DynamicActiveProvider(
            fallbackProvider: fallbackProvider,
            coordinator: coordinator
        )
        self.catalog = ProviderCatalog(providers: [dynamicProvider])

        let providerRuntime = ProviderRuntime(
            provider: dynamicProvider,
            eventLog: idempotentLog,
            logger: logger
        )
        let configuration = ProviderConfiguration(
            providerID: dynamicProvider.identity.id,
            endpointURL: nil,
            defaultModel: dynamicProvider.identity.models.first?.id ?? ModelID(rawValue: "fake-text")
        )
        try await providerRuntime.configure(configuration)
        try await providerRuntime.ready()
        self.providerRuntime = providerRuntime

        let moduleCatalog = ModuleCatalog()
        for mod in modules {
            try await moduleCatalog.register(mod)
        }
        for tool in tools {
            try await moduleCatalog.register(ToolModule(tool: tool))
        }

        let moduleRuntime = ModuleRuntime(
            catalog: moduleCatalog,
            grantedCapabilities: [.read, .write, .execute],
            eventLog: idempotentLog,
            logger: logger
        )
        self.moduleCatalog = moduleCatalog
        self.moduleRuntime = moduleRuntime
        self.skillRuntime = SkillRuntime()

        let store: any MemoryStore
        if let memoryStore {
            store = memoryStore
        } else {
            store = try FileBackedMemoryStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        }
        self.memoryStore = store

        let memoryRuntime = MemoryRuntime(
            store: store,
            eventLog: idempotentLog
        )
        self.memoryRuntime = memoryRuntime

        let mutStore: any MutationEvidenceStore
        if let mutationEvidenceStore {
            mutStore = mutationEvidenceStore
        } else {
            mutStore = try FileBackedMutationStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        }

        let coordination = KernelCoordinationBoundary(
            modules: moduleRuntime
        )

        let agentRuntime = try await AgentRuntime(
            identity: identity,
            eventLog: idempotentLog,
            logger: logger,
            coordination: coordination,
            mutationEvidenceStore: mutStore
        )
        try await agentRuntime.start()
        self.runtime = agentRuntime

        self.session = DefaultAgentSession(runtime: agentRuntime, logger: logger)

        self.orchestrator = M6Orchestrator(
            runtime: agentRuntime,
            eventLog: idempotentLog,
            logger: logger,
            reasoner: LLMReasoner(provider: providerRuntime),
            policy: policy,
            approvalGate: approvalGate,
            moduleRuntime: moduleRuntime
        )

        let rStore: any RunStore = try runStore ?? FileBackedRunStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        let aStore: any ExecutionAttemptStore = try attemptStore ?? FileBackedExecutionAttemptStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        let cStore: any RunCheckpointStore = try checkpointStore ?? FileBackedRunCheckpointStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)
        let jStore: any StateJournalStore = try journalStore ?? FileBackedStateJournalStore(directoryURL: persistenceContainer.agentDurableDirectoryURL)

        self.runStore = rStore
        self.attemptStore = aStore
        self.checkpointStore = cStore
        self.journalStore = jStore

        let boundary = ExecutionBoundary(
            attemptStore: aStore,
            policy: policy ?? DefaultPolicyEvaluator(),
            approvalGate: approvalGate,
            moduleRuntime: moduleRuntime,
            evidenceResolver: evidenceResolver,
            eventLog: idempotentLog,
            targetCapabilities: targetCapabilities
        )
        self.executionBoundary = boundary

        self.lifecycleManager = RunLifecycleManager(
            runtime: agentRuntime,
            runStore: rStore,
            checkpointStore: cStore,
            journalStore: jStore,
            executionBoundary: boundary,
            eventLog: idempotentLog,
            logger: logger,
            reasoner: LLMReasoner(provider: providerRuntime)
        )

        self.recoveryEngine = RunRecoveryEngine(
            runtime: agentRuntime,
            runStore: rStore,
            attemptStore: aStore,
            checkpointStore: cStore,
            journalStore: jStore,
            executionBoundary: boundary,
            eventLog: idempotentLog,
            logger: logger
        )
    }
}

public struct MemorySnapshotItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let content: String

    public init(id: String, kind: String, content: String) {
        self.id = id
        self.kind = kind
        self.content = content
    }
}

extension M8CompositionRoot {
    public func discoverSkills(query: String = "") async throws -> [SkillManifest] {
        try await skillRuntime.discover(query: query)
    }

    public func selectSkill(goalStatement: String) async throws -> SkillID {
        try await skillRuntime.select(goalStatement: goalStatement)
    }

    public func executeSkill(
        id: SkillID,
        inputJSON: String,
        policy: (any PolicyEvaluating)? = nil
    ) async throws -> String {
        try await skillRuntime.execute(
            id: id,
            inputJSON: inputJSON,
            policy: policy ?? DefaultPolicyEvaluator()
        )
    }

    public func memorySnapshot(limit: Int = 50) async throws -> [MemorySnapshotItem] {
        let result = try await memoryRuntime.query(
            MemoryQuery(limit: max(1, limit), sortOrder: .createdAtDescending)
        )
        return result.records.map {
            MemorySnapshotItem(id: $0.id.rawValue, kind: $0.kind.rawValue, content: $0.content)
        }
    }

    public func remember(_ content: String, kind: String = "fact") async throws {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MemoryError.invalidRecord("content") }
        let memoryKind = MemoryKind(rawValue: kind) ?? .fact
        try await memoryRuntime.capture(
            MemoryRecord(
                kind: memoryKind,
                content: value,
                provenance: Provenance(source: "user"),
                scope: .agent,
                importance: 0.8
            )
        )
    }

    public func clearMemory() async throws {
        try await memoryRuntime.clear()
    }

    public var selectedProviderID: String {
        catalog.identities.first?.id.rawValue ?? "none"
    }

    public func currentProviderIdentityID() async -> String {
        do {
            if let engine = try await localModelRuntimeCoordinator.activeLocalModelEngine() {
                return "local-\(engine.identity.id.rawValue)"
            }
        } catch {
            return "local-error"
        }
        return catalog.identities.first?.id.rawValue ?? "none"
    }

    public func currentProviderLifecycle() async -> String {
        do {
            if let engine = try await localModelRuntimeCoordinator.activeLocalModelEngine() {
                let state = await engine.lifecycleState
                switch state {
                case .unloaded: return "unloaded"
                case .loading(let p): return "loading(\(Int(p * 100))%)"
                case .loaded: return "loaded"
                case .unloading: return "unloading"
                case .failed(let r): return "failed(\(r))"
                }
            }
        } catch {
            return "error(\(error.localizedDescription))"
        }
        if let providerRuntime {
            return await providerRuntime.lifecycle.rawValue
        }
        return "unconfigured"
    }

    public func registeredModuleIDs() async -> [String] {
        await moduleCatalog.contracts().map(\.id.rawValue)
    }

    public func activeLocalModelEngine() async throws -> (any LocalModelEngine)? {
        try await localModelRuntimeCoordinator.activeLocalModelEngine()
    }

    public func loadActiveLocalModel(options: LocalModelLoadingOptions? = nil) async throws -> any LocalModelEngine {
        try await localModelRuntimeCoordinator.loadActiveModel(options: options)
    }

    public func unloadActiveLocalModel() async throws {
        try await localModelRuntimeCoordinator.unloadActiveModel()
    }

    public func setActiveLocalModel(id: ModelID?) async throws {
        try await localModelRuntimeCoordinator.setActiveModel(id: id)
    }

    public func deleteLocalModel(id: ModelID) async throws {
        try await localModelRuntimeCoordinator.deleteModel(id: id)
    }
}