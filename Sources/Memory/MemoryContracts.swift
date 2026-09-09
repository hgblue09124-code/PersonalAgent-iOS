import Foundation
import PAFoundation
import PAStorage
import PAEvents

public enum MemoryKind: String, Sendable, Codable, CaseIterable {
    case working
    case episodic
    case semantic
    case preference
    case procedural
}

public enum MemoryLifecycleStage: String, Sendable, Codable, CaseIterable {
    case capture
    case validate
    case store
    case retrieve
    case consolidate
    case update
    case forget
}

public struct MemoryRecord: Sendable, Codable, Equatable {
    public let id: MemoryRecordID
    public let kind: MemoryKind
    public let content: String
    public let provenance: Provenance
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: MemoryRecordID = MemoryRecordID(),
        kind: MemoryKind,
        content: String,
        provenance: Provenance,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol MemoryStore: Sendable {
    func capture(_ record: MemoryRecord) async throws
    func retrieve(id: MemoryRecordID) async throws -> MemoryRecord?
    func retrieve(kind: MemoryKind, limit: Int) async throws -> [MemoryRecord]
    func update(_ record: MemoryRecord) async throws
    func forget(id: MemoryRecordID, reason: String) async throws
}

public protocol WorkingMemory: Sendable {
    func put(key: String, value: String) async
    func get(key: String) async -> String?
    func clear() async
}

public protocol EpisodicMemory: MemoryStore {}
public protocol SemanticMemory: MemoryStore {}
public protocol PreferenceMemory: MemoryStore {}
public protocol ProceduralMemory: MemoryStore {}
