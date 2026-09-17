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

/// Canonical M6 Composition Root wiring M6Orchestrator, AgentRuntime, Subsystem Runtimes, and Events.
/// Production composition uses clean explicit dependency injection without test-fixture pollution.
public struct M6CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let eventLog: InMemoryEventLog
    public let providerRuntime: ProviderRuntime?
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime
    public let memoryStore: any MemoryStore
    public let memoryRuntime: MemoryRuntime
    public let orchestrator: M6Orchestrator

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal M6"),
        logger: any AgentLogger = NullLogger(),
        eventLog: (any EventLog)? = nil,
        provider: (any LLMProvider)? = nil,
        memoryStore: (any MemoryStore)? = nil,
        storeDirectoryURL: URL? = nil,
        policy: (any PolicyEvaluating)? = nil,
        approvalGate: (any ApprovalGate)? = nil,
        modules: [any Module] = [],
        tools: [any Tool] = []
    ) async throws {
        let log = (eventLog as? InMemoryEventLog) ?? InMemoryEventLog()
        self.milestone = .m6
        self.logger = logger
        self.eventLog = log

        // 1. Provider setup
        let activeProvider = provider ?? DeterministicFakeProvider()
        self.catalog = ProviderCatalog(providers: [activeProvider])

        let providerRuntime = ProviderRuntime(
            provider: activeProvider,
            eventLog: log,
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

        // 2. Module setup (clean production registration, no test fixtures)
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
            eventLog: log,
            logger: logger
        )
        self.moduleCatalog = moduleCatalog
        self.moduleRuntime = moduleRuntime

        // 3. Memory setup
        let store: any MemoryStore
        if let memoryStore {
            store = memoryStore
        } else {
            let defaultDirectory: URL
            if let storeDirectoryURL {
                defaultDirectory = storeDirectoryURL
            } else {
                guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw MemoryError.persistenceFailed("Unable to resolve Application Support directory for PAMemory")
                }
                defaultDirectory = appSupport.appendingPathComponent("PersonalAgent/PAMemoryM6")
            }
            store = try FileBackedMemoryStore(directoryURL: defaultDirectory)
        }
        self.memoryStore = store

        let memoryRuntime = MemoryRuntime(
            store: store,
            eventLog: log
        )
        self.memoryRuntime = memoryRuntime

        // 4. Kernel Coordination & Runtime
        let coordination = KernelCoordinationBoundary(
            policy: policy,
            provider: activeProvider,
            modules: moduleRuntime,
            memory: memoryRuntime
        )

        let agentRuntime = try await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger,
            coordination: coordination
        )
        try await agentRuntime.start()
        self.runtime = agentRuntime

        // 5. M6 Orchestrator
        self.orchestrator = M6Orchestrator(
            runtime: agentRuntime,
            eventLog: log,
            logger: logger,
            policy: policy,
            approvalGate: approvalGate,
            moduleRuntime: moduleRuntime
        )
    }
}
