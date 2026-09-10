import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders
import PAModules
import PASkills
import PATools

/// Wires kernel, provider runtime, and module runtime. No privileged device tools.
public struct M3CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let eventLog: InMemoryEventLog
    public let providerRuntime: ProviderRuntime
    public let catalog: ProviderCatalog
    public let moduleCatalog: ModuleCatalog
    public let moduleRuntime: ModuleRuntime

    public var selectedProviderID: String {
        catalog.identities.first?.id.rawValue ?? "none"
    }

    public func currentProviderIdentityID() async -> String {
        await providerRuntime.identity.id.rawValue
    }

    public func currentProviderLifecycle() async -> String {
        await providerRuntime.lifecycle.rawValue
    }

    public func registeredModuleIDs() async -> [String] {
        await moduleCatalog.contracts().map(\.id.rawValue)
    }

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal"),
        logger: any AgentLogger = NullLogger(),
        provider: any LLMProvider = DeterministicFakeProvider(),
        additionalModules: [any Module] = []
    ) async throws {
        let log = InMemoryEventLog()
        self.milestone = .m3
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

        self.runtime = await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger,
            coordination: KernelCoordinationBoundary(
                provider: provider,
                modules: moduleRuntime
            )
        )
    }
}
