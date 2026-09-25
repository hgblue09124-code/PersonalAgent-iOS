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

/// Per-invocation execution state. Isolated from AgentLifecycle and ProviderLifecycle.
public enum ModuleExecutionState: String, Sendable, Codable, Equatable {
    case idle
    case validating
    case executing
    case completed
    case failed
    case cancelled
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

/// Schema-tagged string map. This is not a Swift generic payload and not a JSON Schema engine.
///
/// Guarantees enforced by ModuleRuntime:
/// - `schema.identifier` must equal the contract input/output schema identifier
/// - each `requiredFields` key must be present and non-blank on input
///
/// Deliberately not guaranteed:
/// - structural typing of field values
/// - unknown-key rejection
/// - JSON Schema / Codable model validation
public struct ModulePayload: Sendable, Equatable, Codable {
    public let schema: SchemaDocument
    public let fields: [String: String]

    public init(schema: SchemaDocument, fields: [String: String] = [:]) {
        self.schema = schema
        self.fields = fields
    }

    public func value(for key: String) -> String? {
        fields[key]
    }
}

public protocol ModuleCataloging: Sendable {
    func register(_ module: any Module) async throws
    func resolve(_ id: ModuleID) async -> (any Module)?
    func contracts() async -> [ModuleContract]
}
