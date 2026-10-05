import Foundation
import PAKernel
import PAProviders
import PAProvidersLocal
import PAProvidersGrok
import PAProvidersOpenAI
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
    private let openAI: any LLMProvider
    private let grok: any LLMProvider

    init(fallback: any LLMProvider, credentials: any CredentialResolving) {
        let openAIConfig = ProviderConfiguration(
            providerID: OpenAIProviderBoundary.providerID,
            endpointURL: OpenAIProviderBoundary.defaultEndpoint,
            defaultModel: OpenAIProviderBoundary.declaredIdentity.models[0].id,
            credential: ProviderCredentialRef(
                providerID: OpenAIProviderBoundary.providerID,
                account: "provider.api-key.openai"
            ),
            maxRetryAttempts: 1
        )
        let grokConfig = ProviderConfiguration(
            providerID: GrokProviderBoundary.providerID,
            endpointURL: GrokProviderBoundary.defaultEndpoint,
            defaultModel: GrokProviderBoundary.declaredIdentity.models[0].id,
            credential: ProviderCredentialRef(
                providerID: GrokProviderBoundary.providerID,
                account: "provider.api-key.grok"
            ),
            maxRetryAttempts: 1
        )
        let network = SecurityNetworkTransport(network: URLSessionNetworkAccess())
        self.openAI = OpenAIProvider(
            transport: network,
            credentials: credentials,
            configuration: openAIConfig
        )
        self.grok = GrokProvider(
            transport: network,
            credentials: credentials,
            configuration: grokConfig
        )
        self.fallback = fallback
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "provider.remote.enabled")
    }

    private var selectedID: String {
        UserDefaults.standard.string(forKey: "provider.remote.id") ?? "openai"
    }

    private var selectedProvider: any LLMProvider {
        selectedID == GrokProviderBoundary.providerID.rawValue ? grok : openAI
    }

    var identity: ProviderIdentity {
        enabled ? selectedProvider.identity : fallback.identity
    }

    var capabilities: ProviderCapabilities {
        enabled ? selectedProvider.capabilities : fallback.capabilities
    }

    var health: ProviderHealth {
        get async {
            guard enabled else { return await fallback.health }
            return await selectedProvider.health
        }
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard enabled else { return try await fallback.complete(request) }
        return try await selectedProvider.complete(request)
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard enabled else { return fallback.stream(request) }
        return selectedProvider.stream(request)
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
    public let skillAgentOrchestrator: SkillAgentOrchestrator
    public let agentStore: FileAgentStore
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

        let credentialStore: any SecretStore = KeychainSecretStore()
        let credentials = SecretStoreCredentials(store: credentialStore)
        let fallbackProvider = ConfiguredRemoteProvider(
            fallback: provider ?? DefaultCompositionProvider(),
            credentials: credentials
        )
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
        let skillDirectoryURL = rootDirectoryURL.appendingPathComponent("Skills", isDirectory: true)
        let skillStore = FileSkillStore(directoryURL: skillDirectoryURL)
        try await skillStore.ensureDefaultSkill()
        self.skillRuntime = SkillRuntime(store: skillStore)
        self.skillAgentOrchestrator = SkillAgentOrchestrator(runtime: self.skillRuntime)

        let agentDirectoryURL = rootDirectoryURL.appendingPathComponent("Agents", isDirectory: true)
        let agentStore = FileAgentStore(directoryURL: agentDirectoryURL)
        try await agentStore.ensureDefaultAgent()
        self.agentStore = agentStore

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
    public func discoverAgents(query: String = "") async throws -> [AgentManifest] {
        try await agentStore.discover(query: query)
    }

    public func loadAgent(id: String) async throws -> AgentManifest {
        try await agentStore.load(id: id)
    }

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

    public func runSkillAgent(
        goalStatement: String,
        inputJSON: String,
        policy: (any PolicyEvaluating)? = nil
    ) async throws -> SkillAgentResult {
        try await skillAgentOrchestrator.run(
            goalStatement: goalStatement,
            inputJSON: inputJSON,
            policy: policy ?? DefaultPolicyEvaluator()
        )
    }

    public func runChatSkillIfMatched(
        goalStatement: String,
        policy: (any PolicyEvaluating)? = nil
    ) async throws -> SkillAgentResult? {
        let agent = try await agentStore.load(id: "personal.default")
        let inputData = try JSONSerialization.data(withJSONObject: ["text": goalStatement], options: [.sortedKeys])
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw KernelError.invalidStateUpdate("Unable to encode chat Skill input")
        }
        do {
            return try await skillAgentOrchestrator.run(
                agent: agent,
                goalStatement: goalStatement,
                inputJSON: inputJSON,
                policy: policy ?? DefaultPolicyEvaluator()
            )
        } catch SkillRuntimeError.noSelection {
            return nil
        }
    }

    public func memoryContext(for queryText: String, limit: Int = 6) async throws -> [String] {
        let value = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let result = try await memoryRuntime.query(
            MemoryQuery(
                scopes: [.agent, .session, .conversation],
                kinds: [.semantic, .preference, .fact, .context, .instruction],
                lifecycles: [.active, .updated],
                textSearch: value,
                minImportance: 0.4,
                limit: max(1, limit),
                sortOrder: .relevance
            )
        )
        return result.records.map { $0.content }
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