import PAFoundation
import PAModules
import PATools

/// Adapts a Tool into an atomic Module so ModuleRuntime can execute it.
/// The tool contract remains the source of identity and capabilities.
public struct ToolModule: Module {
    public let contract: ModuleContract
    private let tool: any Tool

    public init(tool: any Tool) {
        self.tool = tool
        let manifest = tool.manifest
        self.contract = ModuleContract(
            id: ModuleID(rawValue: "tool." + manifest.id.rawValue),
            name: manifest.name,
            version: manifest.version,
            kind: .atomic,
            capabilities: manifest.requiredCapabilities,
            inputSchema: manifest.inputSchema,
            outputSchema: manifest.outputSchema,
            requiredFields: ["arguments"]
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        let arguments = input.value(for: "arguments") ?? ""
        let output = try await tool.run(argumentsJSON: arguments)
        return ModulePayload(schema: contract.outputSchema, fields: ["output": output])
    }
}
