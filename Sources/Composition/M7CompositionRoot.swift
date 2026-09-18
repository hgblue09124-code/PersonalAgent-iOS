import Foundation
import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAModules
import PASkills
import PATools
import PAMemory
import PAPolicy
import PACognition
import PAAgency

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
        policy: (any PolicyEvaluating)? = nil,
        approvalGate: (any ApprovalGate)? = nil,
        evidenceResolver: (any ExecutionEvidenceResolver)? = nil,
        targetCapabilities: [ExecutionTargetCapability]? = nil,
        modules: [any Module] = [],
        tools: [any Tool] = [],
        runStore: (any RunStore)? = nil,
        attemptStore: (any ExecutionAttemptStore)? = nil,
        checkpointStore: (any RunCheckpointStore)? = nil,
        journalStore: (any StateJournalStore)? = nil
    ) async throws {
        let rawLog = eventLog ?? InMemoryEventLog()
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

        let store = memoryStore ?? InMemoryMemoryStore()
        self.memoryStore = store

        let memoryRuntime = MemoryRuntime(
            store: store,
            eventLog: idempotentLog
        )
        self.memoryRuntime = memoryRuntime

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
            coordination: coordination
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

        let rStore = runStore ?? InMemoryRunStore()
        let aStore = attemptStore ?? InMemoryExecutionAttemptStore()
        let cStore = checkpointStore ?? InMemoryRunCheckpointStore()
        let jStore = journalStore ?? InMemoryStateJournalStore()

        self.runStore = rStore
        self.attemptStore = aStore
        self.checkpointStore = cStore
        self.journalStore = jStore

        let capabilities: [ExecutionTargetCapability]
        if let targetCapabilities {
            capabilities = targetCapabilities
        } else {
            var autoCaps: [ExecutionTargetCapability] = [
                ExecutionTargetCapability(
                    toolID: ToolID(rawValue: "echo"),
                    idempotencyClass: .idempotent,
                    supportsEvidenceResolution: evidenceResolver != nil
                ),
                ExecutionTargetCapability(
                    toolID: ToolID(rawValue: "tool.echo"),
                    idempotencyClass: .idempotent,
                    supportsEvidenceResolution: evidenceResolver != nil
                )
            ]
            for tool in tools {
                autoCaps.append(
                    ExecutionTargetCapability(
                        toolID: tool.manifest.id,
                        idempotencyClass: .idempotent,
                        supportsEvidenceResolution: evidenceResolver != nil
                    )
                )
            }
            capabilities = autoCaps
        }

        let boundary = ExecutionBoundary(
            attemptStore: aStore,
            policy: policy ?? DefaultPolicyEvaluator(),
            approvalGate: approvalGate,
            moduleRuntime: moduleRuntime,
            evidenceResolver: evidenceResolver,
            eventLog: idempotentLog,
            targetCapabilities: capabilities
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
