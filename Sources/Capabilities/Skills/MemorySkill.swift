import Foundation
import PAKernel
import PAModules
import PAMemory

/// Minimal Skill model: Grammar + 1 Rule = 1 Skill.
/// A Skill describes one executable capability; execution remains behind Module.
public struct SkillDefinition: Sendable, Equatable {
    public let id: String
    public let grammar: String
    public let rule: String
    public let moduleID: ModuleID

    public init(id: String, grammar: String, rule: String, moduleID: ModuleID) {
        self.id = id
        self.grammar = grammar
        self.rule = rule
        self.moduleID = moduleID
    }
}

public protocol Skill: Sendable {
    static var definition: SkillDefinition { get }
}

public struct SkillCatalog: Sendable {
    private var definitions: [String: SkillDefinition] = [:]

    public init() {}

    public mutating func register<S: Skill>(_ skill: S.Type) {
        definitions[skill.definition.id] = skill.definition
    }

    public func resolve(id: String) -> SkillDefinition? {
        definitions[id]
    }

    public var all: [SkillDefinition] {
        definitions.values.sorted { $0.id < $1.id }
    }
}

/// Memory Skill: skill-facing boundary for chat memory capture/retrieval.
/// Persistence remains owned by MemoryRuntime.
public struct MemorySkillModule: Module, Skill {
    public static let id = ModuleID(rawValue: "skill.memory")
    public static let definition = SkillDefinition(
        id: "skill.memory",
        grammar: "memory",
        rule: "capture or retrieve conversation memory",
        moduleID: Self.id
    )
    private enum Action: String { case capture, retrieve }
    private let memory: MemoryRuntime
    public let contract: ModuleContract

    public init(memory: MemoryRuntime) {
        self.memory = memory
        self.contract = ModuleContract(
            id: Self.id, name: "Memory",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .meso, capabilities: [.read, .write, .execute],
            inputSchema: SchemaDocument(identifier: "skill.memory.in"),
            outputSchema: SchemaDocument(identifier: "skill.memory.out"),
            requiredFields: ["action", "conversationID"]
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        try Task.checkCancellation()
        guard let action = input.value(for: "action").flatMap(Action.init(rawValue:)) else {
            throw ModuleRuntimeError.invalidInput("action")
        }
        guard let conversationID = input.value(for: "conversationID"), !conversationID.isEmpty else {
            throw ModuleRuntimeError.invalidInput("conversationID")
        }
        switch action {
        case .capture:
            guard let role = input.value(for: "role"), !role.isEmpty else { throw ModuleRuntimeError.invalidInput("role") }
            guard let content = input.value(for: "content"), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ModuleRuntimeError.invalidInput("content")
            }
            let record = MemoryRecord(
                kind: role == "user" ? .event : .context,
                content: content,
                provenance: Provenance(source: "chat"),
                scope: .conversation,
                importance: role == "user" ? 0.7 : 0.5,
                metadata: MemoryMetadata(storage: ["conversationID": conversationID, "role": role])
            )
            try await memory.capture(record)
            return ModulePayload(schema: contract.outputSchema, fields: ["status": "captured", "recordID": record.id.rawValue])
        case .retrieve:
            let limit = max(1, min(Int(input.value(for: "limit") ?? "40") ?? 40, 200))
            let result = try await memory.query(MemoryQuery(
                scopes: [.conversation], lifecycles: [.active, .updated],
                metadataFilters: ["conversationID": conversationID],
                limit: limit, sortOrder: .createdAtAscending
            ))
            let records = result.records.map {
                ChatMemoryItem(id: $0.id.rawValue, role: $0.metadata["role"] ?? "context", content: $0.content, createdAt: $0.createdAt)
            }
            let data = try JSONEncoder.chatMemory.encode(records)
            return ModulePayload(schema: contract.outputSchema, fields: ["status": "retrieved", "items": String(data: data, encoding: .utf8) ?? "[]"])
        }
    }
}

public struct ChatMemoryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: String
    public let content: String
    public let createdAt: Date
    public init(id: String, role: String, content: String, createdAt: Date) {
        self.id = id; self.role = role; self.content = content; self.createdAt = createdAt
    }
}

private extension JSONEncoder {
    static var chatMemory: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }
}
