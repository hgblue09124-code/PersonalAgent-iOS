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

public enum ModuleRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownModule(ModuleID)
    case duplicateRegistration(ModuleID)
    case invalidInput(String)
    case invalidOutput(String)
    case capabilityDenied(CapabilityLevel)
    case unavailable(ModuleID)
    case timeout
    case cancelled
    case invalidState(ModuleExecutionState)
    case executionFailed(String)
    case compositionFailed(String)
    case missingDependency(module: ModuleID, missing: ModuleID)
    case dependencyCycle([ModuleID])

    public var description: String {
        switch self {
        case .unknownModule(let id): return "unknownModule:\(id.rawValue)"
        case .duplicateRegistration(let id): return "duplicateRegistration:\(id.rawValue)"
        case .invalidInput(let reason): return "invalidInput:\(reason)"
        case .invalidOutput(let reason): return "invalidOutput:\(reason)"
        case .capabilityDenied: return "capabilityDenied"
        case .unavailable(let id): return "unavailable:\(id.rawValue)"
        case .timeout: return "timeout"
        case .cancelled: return "cancelled"
        case .invalidState(let state): return "invalidState:\(state.rawValue)"
        case .executionFailed(let reason): return "executionFailed:\(reason)"
        case .compositionFailed(let reason): return "compositionFailed:\(reason)"
        case .missingDependency(let module, let missing):
            return "missingDependency:\(module.rawValue)->\(missing.rawValue)"
        case .dependencyCycle(let ids):
            return "dependencyCycle:\(ids.map(\\.rawValue).joined(separator: ","))"
        }
    }
}

public protocol Module: Sendable {
    var contract: ModuleContract { get }
    func execute(_ input: ModulePayload) async throws -> ModulePayload
}

public protocol ModuleHealthReporting: Sendable {
    func status() async -> ModuleLifecycle
}

public protocol ModuleCataloging: Sendable {
    func register(_ module: any Module) async throws
    func resolve(_ id: ModuleID) async -> (any Module)?
    func contracts() async -> [ModuleContract]
}
