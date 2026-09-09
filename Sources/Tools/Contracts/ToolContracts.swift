import PAFoundation
import PAPolicy
import PAObservability

/// A Tool is an executable capability with typed input/output.
/// It is not a Skill and it does not own agent state.
public struct ToolManifest: Hashable, Sendable, Codable {
    public let id: ToolID
    public let name: String
    public let version: SemanticVersion
    public let requiredCapabilities: CapabilityLevel
    public let inputSchema: SchemaDocument
    public let outputSchema: SchemaDocument

    public init(
        id: ToolID,
        name: String,
        version: SemanticVersion,
        requiredCapabilities: CapabilityLevel,
        inputSchema: SchemaDocument,
        outputSchema: SchemaDocument
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.requiredCapabilities = requiredCapabilities
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }
}

public struct ToolInvocation: Sendable, Equatable {
    public let toolID: ToolID
    public let argumentsJSON: String
    public let intent: ActionIntent

    public init(toolID: ToolID, argumentsJSON: String, intent: ActionIntent) {
        self.toolID = toolID
        self.argumentsJSON = argumentsJSON
        self.intent = intent
    }
}

public struct ToolResult: Sendable, Equatable {
    public let toolID: ToolID
    public let outputJSON: String
    public let succeeded: Bool

    public init(toolID: ToolID, outputJSON: String, succeeded: Bool) {
        self.toolID = toolID
        self.outputJSON = outputJSON
        self.succeeded = succeeded
    }
}

/// Tools never bypass Policy.
public protocol ToolExecuting: Sendable {
    func execute(_ invocation: ToolInvocation, policy: any PolicyEvaluating) async throws -> ToolResult
}

public protocol ToolCatalog: Sendable {
    func manifest(for id: ToolID) async -> ToolManifest?
}

public protocol Tool: Sendable {
    var manifest: ToolManifest { get }
    func run(argumentsJSON: String) async throws -> String
}

public struct EchoTool: Tool {
    public let manifest: ToolManifest

    public init() {
        self.manifest = ToolManifest(
            id: ToolID(rawValue: "echo"),
            name: "Echo",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            requiredCapabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "tool.echo.in"),
            outputSchema: SchemaDocument(identifier: "tool.echo.out")
        )
    }

    public func run(argumentsJSON: String) async throws -> String {
        argumentsJSON
    }
}
