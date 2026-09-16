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
public struct M6CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let eventLog: InMemoryEventLog
    public let providerRuntime: ProviderRuntime
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime
    public let memoryStore: any MemoryStore
    public let memoryRuntime: MemoryRuntime
    public let orchestrator: M6Orchestrator

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal M6"),
        logger: any AgentLogger = NullLogger(),
        provider: any LLMProvider = DeterministicFakeProvider(),
        memoryStore: (any MemoryStore)? = nil,
        storeDirectoryURL: URL? = nil,
        policy: (any PolicyEvaluating)? = nil,
        additionalModules: [any Module] = []
    ) async throws {
        let log = InMemoryEventLog()
        self.milestone = .m6
        self.logger = logger
        self.eventLog = log
        self.catalog = ProviderCatalog(providers: [provider])

        let providerRuntime = ProviderRuntime(
            provider: provider,
            eventLog: log,
            logger: logger
        )
        let configuration = ProviderConfiguration(
            providerID: provider.identity.id,
            endpointURL: nil,
            defaultModel: provider.identity.models.first?.id ?? ModelID(rawValue: "fake-text")
        )
        try await providerRuntime.configure(configuration)
        try await providerRuntime.ready()
        self.providerRuntime = providerRuntime

        let moduleCatalog = ModuleCatalog()
        try await moduleCatalog.register(EchoModule())
        try await moduleCatalog.register(ValidationRejectModule())
        try await moduleCatalog.register(PrivilegedModule())
        try await moduleCatalog.register(HangModule())
        try await moduleCatalog.register(FailingModule())
        try await moduleCatalog.register(ToolModule(tool: EchoTool()))
        for module in additionalModules {
            try await moduleCatalog.register(module)
        }
        let moduleRuntime = ModuleRuntime(
            catalog: moduleCatalog,
            grantedCapabilities: [.read, .write, .execute],
            eventLog: log,
            logger: logger
        )
        try await moduleCatalog.register(EchoSkillModule(runtime: moduleRuntime))
        self.moduleCatalog = moduleCatalog
        self.moduleRuntime = moduleRuntime

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

        let agentRuntime = try await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger,
            coordination: KernelCoordinationBoundary(
                provider: provider,
                modules: moduleRuntime,
                memory: memoryRuntime
            )
        )
        try await agentRuntime.start()
        self.runtime = agentRuntime

        self.orchestrator = M6Orchestrator(
            runtime: agentRuntime,
            eventLog: log,
            logger: logger,
            policy: policy,
            moduleRuntime: moduleRuntime
        )
    }
}
