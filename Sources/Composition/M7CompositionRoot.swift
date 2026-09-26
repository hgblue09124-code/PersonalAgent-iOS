import PARuntime
import Foundation
import PAKernel
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAModules
import PASkills
import PATools
import PAMemory
import PAStorageMemory
import PARuntime

/// Canonical M7 Composition Root wiring Durable Run Lifecycle, ExecutionBoundary,
/// RunLifecycleManager, RunRecoveryEngine, Stores, and IdempotentEventLog.
public struct M7CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
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
        identity: AgentIdentity = AgentIdentity(displayName: "Personal M7"),
        logger: any AgentLogger = NullLoggerBridge(),
        eventLog: (any EventLog)? = nil,
        provider: (any LLMProvider)? = nil,
        memoryStore: (any MemoryStore)? = nil,
        storeDirectoryURL: URL? = nil,
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
        let resolvedDirectoryURL: URL?
        if let storeDirectoryURL {
            resolvedDirectoryURL = storeDirectoryURL
        } else if runStore == nil || attemptStore == nil || checkpointStore == nil || journalStore == nil {
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                resolvedDirectoryURL = appSupport.appendingPathComponent("PersonalAgent/M7Stores")
            } else {
                resolvedDirectoryURL = nil
            }
        } else {
            resolvedDirectoryURL = nil
        }

        let rawLog: any EventLog
        if let eventLog {
            rawLog = eventLog
        } else if let dir = resolvedDirectoryURL {
            rawLog = try FileBackedEventLog(directoryURL: dir)
        } else {
            rawLog = InMemoryEventLog()
        }

        let idempotentLog = IdempotentEventLog(innerLog: rawLog)
        self.milestone = .m7
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
        } else if let dir = resolvedDirectoryURL {
            store = try FileBackedMemoryStore(directoryURL: dir)
        } else {
            store = InMemoryMemoryStore()
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
        } else if let dir = resolvedDirectoryURL {
            mutStore = try FileBackedMutationStore(directoryURL: dir)
        } else {
            mutStore = InMemoryMutationEvidenceStore()
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

        self.orchestrator = M6Orchestrator(
            runtime: agentRuntime,
            eventLog: idempotentLog,
            logger: logger,
            policy: policy,
            approvalGate: approvalGate,
            moduleRuntime: moduleRuntime
        )

        let rStore: any RunStore
        if let runStore {
            rStore = runStore
        } else if let dir = resolvedDirectoryURL {
            rStore = try FileBackedRunStore(directoryURL: dir)
        } else {
            rStore = InMemoryRunStore()
        }

        let aStore: any ExecutionAttemptStore
        if let attemptStore {
            aStore = attemptStore
        } else if let dir = resolvedDirectoryURL {
            aStore = try FileBackedExecutionAttemptStore(directoryURL: dir)
        } else {
            aStore = InMemoryExecutionAttemptStore()
        }

        let cStore: any RunCheckpointStore
        if let checkpointStore {
            cStore = checkpointStore
        } else if let dir = resolvedDirectoryURL {
            cStore = try FileBackedRunCheckpointStore(directoryURL: dir)
        } else {
            cStore = InMemoryRunCheckpointStore()
        }

        let jStore: any StateJournalStore
        if let journalStore {
            jStore = journalStore
        } else if let dir = resolvedDirectoryURL {
            jStore = try FileBackedStateJournalStore(directoryURL: dir)
        } else {
            jStore = InMemoryStateJournalStore()
        }

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
