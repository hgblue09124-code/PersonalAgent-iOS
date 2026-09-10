import PAFoundation
import PAModules
import PATools
import PAPolicy

/// A Skill is a higher-level compositional capability.
/// It may compose Modules/Tools through their contracts. It must not bypass them.
/// A Skill is not a Tool.
///
/// M3 execution path is Skill-as-Module (`EchoSkillModule`) → `ModuleRuntime`.
/// `SkillStore` / `SkillSelecting` / `SkillExecuting` / `SkillVerifying` are
/// future seams. They are not a second runtime.

public struct SkillManifest: Hashable, Sendable, Codable {
    public let id: SkillID
    public let name: String
    public let description: String
    public let version: SemanticVersion
    public let instructions: String
    public let inputSchema: SchemaDocument
    public let outputSchema: SchemaDocument
    public let requiredCapabilities: CapabilityLevel
    public let tools: [ToolID]
    public let dependencies: [SkillID]
    public let metadata: [String: String]

    public init(
        id: SkillID,
        name: String,
        description: String,
        version: SemanticVersion,
        instructions: String,
        inputSchema: SchemaDocument,
        outputSchema: SchemaDocument,
        requiredCapabilities: CapabilityLevel,
        tools: [ToolID] = [],
        dependencies: [SkillID] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.instructions = instructions
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.requiredCapabilities = requiredCapabilities
        self.tools = tools
        self.dependencies = dependencies
        self.metadata = metadata
    }
}

public enum SkillCompositionKind: String, Sendable, Codable {
    case atomicModule
    case skill
    case compositeSkill
    case workflow
    case goal
}

public enum SkillSourceKind: String, Sendable, Codable {
    case localStorage
    case remoteRepository
    case gitHub
    case externalOcean
}

public protocol SkillStore: Sendable {
    func discover(query: String) async throws -> [SkillManifest]
    func load(id: SkillID) async throws -> SkillManifest
}

public protocol SkillSelecting: Sendable {
    func select(goalStatement: String, available: [SkillManifest]) async throws -> SkillID?
}

public protocol SkillExecuting: Sendable {
    func execute(id: SkillID, inputJSON: String, policy: any PolicyEvaluating) async throws -> String
}

public protocol SkillVerifying: Sendable {
    func verify(id: SkillID, outputJSON: String) async throws -> Bool
}
