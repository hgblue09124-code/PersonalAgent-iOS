import PAFoundation
import PAArchitecture
import PAKernel
import PAObservability
import PAEvents
import PAProviders

/// Wires kernel + provider runtime. Does not load production credentials or open a network session.
public struct M2CompositionRoot: CompositionRoot, Sendable {
    public let milestone: MilestoneGate
    public let logger: any AgentLogger
    public let runtime: AgentRuntime
    public let eventLog: InMemoryEventLog
    public let providerRuntime: ProviderRuntime
    public let catalog: ProviderCatalog

    public var selectedProviderID: String {
        catalog.identities.first?.id.rawValue ?? "none"
    }

    public init(
        identity: AgentIdentity = AgentIdentity(displayName: "Personal"),
        logger: any AgentLogger = NullLogger(),
        provider: any LLMProvider = DeterministicFakeProvider()
    ) async {
        let log = InMemoryEventLog()
        self.milestone = .m2
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
        try? await providerRuntime.configure(configuration)
        try? await providerRuntime.ready()
        self.providerRuntime = providerRuntime
        self.runtime = await AgentRuntime(
            identity: identity,
            eventLog: log,
            logger: logger,
            coordination: KernelCoordinationBoundary(provider: provider)
        )
    }
}
