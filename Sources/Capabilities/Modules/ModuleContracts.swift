import PAFoundation
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

public struct ModuleInvocation: Sendable, Equatable {
    public let moduleID: ModuleID
    public let input: ModulePayload
    public let timeoutNanoseconds: UInt64?

    public init(moduleID: ModuleID, input: ModulePayload, timeoutNanoseconds: UInt64? = nil) {
        self.moduleID = moduleID
        self.input = input
        self.timeoutNanoseconds = timeoutNanoseconds
    }
}

public struct ModuleResult: Sendable, Equatable {
    public let moduleID: ModuleID
    public let output: ModulePayload
    public let state: ModuleExecutionState

    public init(moduleID: ModuleID, output: ModulePayload, state: ModuleExecutionState = .completed) {
        self.moduleID = moduleID
        self.output = output
        self.state = state
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
            return "dependencyCycle:\(ids.map(\.rawValue).joined(separator: ","))"
        }
    }
}

/// A module is an explicit capability boundary.
/// Implementations must check `Task.checkCancellation()` at await points.
/// Timeout and cancellation are cooperative; the runtime does not hard-preempt a
/// module body that never suspends.
public protocol Module: Sendable {
    var contract: ModuleContract { get }
    func execute(_ input: ModulePayload) async throws -> ModulePayload
}

public protocol ModuleHealthReporting: Sendable {
    func status() async -> ModuleLifecycle
}

/// Kernel and skills invoke modules through this port. Not a service locator.
public protocol ModuleExecuting: Sendable {
    func execute(_ invocation: ModuleInvocation) async throws -> ModuleResult
}

public protocol ModuleCataloging: Sendable {
    func register(_ module: any Module) async throws
    func resolve(_ id: ModuleID) async -> (any Module)?
    func contracts() async -> [ModuleContract]
}
