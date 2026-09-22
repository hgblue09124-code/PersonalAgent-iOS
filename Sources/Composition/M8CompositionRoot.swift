import Foundation
import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAProvidersLocal
import PAModules
import PASkills
import PATools
import PAMemory
import PAPolicy
import PACognition
import PAAgency
import PASecurity

/// Canonical M8 Composition Root assembling the Agent OS runtime into a Personal Agent product architecture.
/// Wires M7 Durable Execution Lifecycle, M8 AgentSession, Local Model Contracts, Device Capabilities, and Domain Persistence.
public struct M8CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let session: any AgentSession
    public let deviceCapabilityProvider: any DeviceCapabilityProviding
    public let persistenceContainer: ProductPersistenceContainer
    public let localModelStorage: any LocalModelStorage
    public let eventLog: any EventLog
    public let idempotentEventLog: IdempotentEventLog
    public let providerRuntime: ProviderRuntime?
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime
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

        if let localModelStorage {
            self.localModelStorage = localModelStorage
        } else {
            let modelsDir = persistenceContainer.modelMetadataDirectoryURL.appendingPathComponent("Models")
            self.localModelStorage = try FileBackedLocalModelStorage(modelsDirectoryURL: modelsDir)
        }

        let resolvedDeviceCapability = deviceCapabilityProvider ?? DefaultDeviceCapabilityProvider()
        self.deviceCapabilityProvider = resolvedDeviceCapability

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

        let activeProvider = provider ?? DeterministicFakeProvider()
        self.catalog = ProviderCatalog(providers: [activeProvider])

        let providerRuntime = ProviderRuntime(
            provider: activeProvider,
            eventLog: idempotentLog,
            logger: logger
        )
        let configuration = ProviderConfiguration(
            providerID: activeProvider.identity.id,
            endpointURL: nil,
            defaultModel: activeProvider.identity.models.first?.id ?? ModelID(rawValue: "fake-text")
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
            policy: policy,
            provider: activeProvider,
            modules: moduleRuntime,
            memory: memoryRuntime
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
            logger: logger
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

extension M8CompositionRoot {
    public var selectedProviderID: String {
        catalog.identities.first?.id.rawValue ?? "none"
    }

    public func currentProviderIdentityID() async -> String {
        catalog.identities.first?.id.rawValue ?? "none"
    }

    public func currentProviderLifecycle() async -> String {
        if let providerRuntime {
            return await providerRuntime.lifecycle.rawValue
        }
        return "unconfigured"
    }

    public func registeredModuleIDs() async -> [String] {
        await moduleCatalog.contracts().map(\.id.rawValue)
    }
}
