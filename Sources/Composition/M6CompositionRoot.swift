import Foundation
import PAFoundation
import PAArchitecture
import PAKernel
import PAPolicy
import PAObservability
import PAEvents
import PAProviders
import PAModules
import PASkills
import PATools
import PAMemory

public struct PermissivePolicyEvaluator: PolicyEvaluating {
    public init() {}
    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .allow("Permissive policy")
    }
}

public struct DenyingPolicyEvaluator: PolicyEvaluating {
    public init() {}
    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .deny("Policy denied")
    }
}

/// M6 Production Composition Root wiring M6 responsibilities explicitly.
/// Does NOT hard-wire fake or test modules.
public struct M6CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let orchestrator: M6Orchestrator
    public let policy: any PolicyEvaluating
    public let eventLog: InMemoryEventLog
    public let providerRuntime: ProviderRuntime?
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime
    public let memoryStore: any MemoryStore
    public let memoryRuntime: MemoryRuntime

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "M6Agent"),
        logger: any AgentLogger = NullLogger(),
        policy: (any PolicyEvaluating)? = nil,
        provider: (any LLMProvider)? = nil,
        memoryStore: (any MemoryStore)? = nil,
        storeDirectoryURL: URL? = nil,
        modules: [any Module] = []
    ) async throws {
        let log = InMemoryEventLog()
        self.milestone = .m6
        self.logger = logger
        self.eventLog = log
        let policyEvaluator = policy ?? PermissivePolicyEvaluator()
        self.policy = policyEvaluator

        if let provider {
            self.catalog = ProviderCatalog(providers: [provider])
            let pRuntime = ProviderRuntime(
                provider: provider,
                eventLog: log,
                logger: logger
            )
            let configuration = ProviderConfiguration(
                providerID: provider.identity.id,
                endpointURL: nil,
                defaultModel: provider.identity.models.first?.id ?? ModelID(rawValue: "default-text")
            )
            try await pRuntime.configure(configuration)
            try await pRuntime.ready()
            self.providerRuntime = pRuntime
        } else {
            self.catalog = ProviderCatalog(providers: [])
            self.providerRuntime = nil
        }

        let moduleCatalog = ModuleCatalog()
        for module in modules {
            try await moduleCatalog.register(module)
        }
        let moduleRuntime = ModuleRuntime(
            catalog: moduleCatalog,
            grantedCapabilities: [.read, .write, .execute],
            eventLog: log,
            logger: logger
        )
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

        let runtime = await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger,
            coordination: KernelCoordinationBoundary(
                policy: policyEvaluator,
                provider: provider,
                modules: moduleRuntime,
                memory: memoryRuntime
            )
        )
        self.runtime = runtime

        self.orchestrator = M6Orchestrator(
            runtime: runtime,
            policy: policyEvaluator,
            approvalGate: nil,
            logger: logger,
            eventLog: log
        )
    }
}
