import PAKernel
import PAPolicy

public enum ModuleKind: String, Sendable, Codable {
    case atomic
    case meso
}

/// Catalog / availability lifecycle. Isolated from a single invocation.
public enum ModuleLifecycle: String, Sendable, Codable {
    case registered
    case loaded
    case active
    case degraded
    case unloaded
    case failed
}

public struct ModuleContract: Hashable, Sendable, Codable {
    public let id: ModuleID
    public let name: String
    public let version: SemanticVersion
    public let kind: ModuleKind
    public let capabilities: CapabilityLevel
    public let dependencies: [ModuleID]
    public let inputSchema: SchemaDocument
    public let outputSchema: SchemaDocument
    public let lifecycle: ModuleLifecycle
    public let requiredFields: [String]

    public init(
        id: ModuleID,
        name: String,
        version: SemanticVersion,
        kind: ModuleKind,
        capabilities: CapabilityLevel,
        dependencies: [ModuleID] = [],
        inputSchema: SchemaDocument,
        outputSchema: SchemaDocument,
        lifecycle: ModuleLifecycle = .registered,
        requiredFields: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.lifecycle = lifecycle
        self.requiredFields = requiredFields
    }
}

public protocol ModuleCataloging: Sendable {
    func register(_ module: any Module) async throws
    func resolve(_ id: ModuleID) async -> (any Module)?
    func contracts() async -> [ModuleContract]
}
