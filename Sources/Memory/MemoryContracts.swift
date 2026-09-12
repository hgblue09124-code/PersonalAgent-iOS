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
    case fact
    case event
    case context
    case instruction
    case observation
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

public enum MemoryScope: String, Sendable, Codable, CaseIterable, Hashable {
    case agent
    case session
    case conversation
    case global
}

public enum MemoryLifecycle: String, Sendable, Codable, CaseIterable, Hashable {
    case created
    case active
    case updated
    case archived
    case deleted
}

public enum MemorySource: String, Sendable, Codable, CaseIterable, Hashable {
    case user
    case agent
    case conversation
    case tool
    case module
    case system
    case importSource
}

public struct MemoryMetadata: Sendable, Codable, Equatable, ExpressibleByDictionaryLiteral {
    public var storage: [String: String]

    public init(storage: [String: String] = [:]) {
        self.storage = storage
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.storage = Dictionary(uniqueKeysWithValues: elements)
    }

    public subscript(key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

public struct MemoryStorageRecord: StorageRecord, Codable, Sendable, Equatable {
    public let record: MemoryRecord

    public var id: String { record.id.rawValue }
    public var updatedAt: Date { record.updatedAt }
    public var version: Int { record.version }
    public var parentVersion: Int? { record.parentVersion }
    public var revisionToken: String { record.revisionToken }
    public var parentRevisionToken: String? { record.parentRevisionToken }
    public var ancestorRevisionTokens: Set<String> { record.ancestorRevisionTokens }

    public init(_ record: MemoryRecord) {
        self.record = record
    }

    public func updatingVersion(_ newVersion: Int, parentVersion: Int?, revisionToken: String, parentRevisionToken: String?, ancestorRevisionTokens: Set<String>) -> MemoryStorageRecord {
        let updatedRecord = MemoryRecord(
            id: record.id,
            kind: record.kind,
            content: record.content,
            provenance: record.provenance,
            createdAt: record.createdAt,
            updatedAt: Date(),
            scope: record.scope,
            lifecycle: record.lifecycle,
            importance: record.importance,
            metadata: record.metadata,
            version: newVersion,
            parentVersion: parentVersion,
            revisionToken: revisionToken,
            parentRevisionToken: parentRevisionToken,
            ancestorRevisionTokens: ancestorRevisionTokens
        )
        return MemoryStorageRecord(updatedRecord)
    }

    public func updatingVersion(_ newVersion: Int, parentVersion: Int?) -> MemoryStorageRecord {
        let newToken = "\(id)-v\(newVersion)"
        var updatedAncestors = record.ancestorRevisionTokens
        updatedAncestors.insert(record.revisionToken)
        let updatedRecord = MemoryRecord(
            id: record.id,
            kind: record.kind,
            content: record.content,
            provenance: record.provenance,
            createdAt: record.createdAt,
            updatedAt: Date(),
            scope: record.scope,
            lifecycle: record.lifecycle,
            importance: record.importance,
            metadata: record.metadata,
            version: newVersion,
            parentVersion: parentVersion,
            revisionToken: newToken,
            parentRevisionToken: record.revisionToken,
            ancestorRevisionTokens: updatedAncestors
        )
        return MemoryStorageRecord(updatedRecord)
    }
}

public struct MemoryRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: MemoryRecordID
    public let kind: MemoryKind
    public let content: String
    public let provenance: Provenance
    public let createdAt: Date
    public let updatedAt: Date
    public let scope: MemoryScope
    public let lifecycle: MemoryLifecycle
    public let importance: Double
    public let metadata: MemoryMetadata
    public let version: Int
    public let parentVersion: Int?
    public let revisionToken: String
    public let parentRevisionToken: String?
    public let ancestorRevisionTokens: Set<String>

    public init(
        id: MemoryRecordID = MemoryRecordID(),
        kind: MemoryKind,
        content: String,
        provenance: Provenance,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scope: MemoryScope = .agent,
        lifecycle: MemoryLifecycle = .active,
        importance: Double = 0.5,
        metadata: MemoryMetadata = MemoryMetadata(),
        version: Int = 1,
        parentVersion: Int? = nil,
        revisionToken: String? = nil,
        parentRevisionToken: String? = nil,
        ancestorRevisionTokens: Set<String> = []
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scope = scope
        self.lifecycle = lifecycle
        self.importance = importance
        self.metadata = metadata
        self.version = version
        self.parentVersion = parentVersion
        self.revisionToken = revisionToken ?? "\(id.rawValue)-v\(version)"
        self.parentRevisionToken = parentRevisionToken
        self.ancestorRevisionTokens = ancestorRevisionTokens
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, content, provenance, createdAt, updatedAt, scope, lifecycle, importance, metadata, version, parentVersion, revisionToken, parentRevisionToken, ancestorRevisionTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(MemoryRecordID.self, forKey: .id)
        self.kind = try container.decode(MemoryKind.self, forKey: .kind)
        self.content = try container.decode(String.self, forKey: .content)
        self.provenance = try container.decode(Provenance.self, forKey: .provenance)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.scope = try container.decode(MemoryScope.self, forKey: .scope)
        self.lifecycle = try container.decode(MemoryLifecycle.self, forKey: .lifecycle)
        self.importance = try container.decode(Double.self, forKey: .importance)
        self.metadata = try container.decode(MemoryMetadata.self, forKey: .metadata)
        self.version = try container.decode(Int.self, forKey: .version)
        self.parentVersion = try container.decodeIfPresent(Int.self, forKey: .parentVersion)
        self.revisionToken = try container.decodeIfPresent(String.self, forKey: .revisionToken) ?? "\(id.rawValue)-v\(version)"
        self.parentRevisionToken = try container.decodeIfPresent(String.self, forKey: .parentRevisionToken)
        self.ancestorRevisionTokens = try container.decodeIfPresent(Set<String>.self, forKey: .ancestorRevisionTokens) ?? []
    }

    public func updating(
        content: String? = nil,
        scope: MemoryScope? = nil,
        lifecycle: MemoryLifecycle? = nil,
        importance: Double? = nil,
        metadata: MemoryMetadata? = nil,
        updatedAt: Date = Date(),
        parentVersion: Int?? = nil,
        revisionToken: String? = nil,
        parentRevisionToken: String?? = nil,
        ancestorRevisionTokens: Set<String>? = nil
    ) -> MemoryRecord {
        MemoryRecord(
            id: id,
            kind: kind,
            content: content ?? self.content,
            provenance: provenance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            scope: scope ?? self.scope,
            lifecycle: lifecycle ?? self.lifecycle,
            importance: importance ?? self.importance,
            metadata: metadata ?? self.metadata,
            version: version,
            parentVersion: parentVersion ?? self.parentVersion,
            revisionToken: revisionToken ?? self.revisionToken,
            parentRevisionToken: parentRevisionToken ?? self.parentRevisionToken,
            ancestorRevisionTokens: ancestorRevisionTokens ?? self.ancestorRevisionTokens
        )
    }
}

public struct MemoryQuery: Sendable, Codable, Equatable {
    public enum SortOrder: String, Sendable, Codable {
        case createdAtDescending
        case createdAtAscending
        case importanceDescending
        case relevance
    }

    public var ids: Set<MemoryRecordID>?
    public var scopes: Set<MemoryScope>?
    public var kinds: Set<MemoryKind>?
    public var lifecycles: Set<MemoryLifecycle>?
    public var startDate: Date?
    public var endDate: Date?
    public var textSearch: String?
    public var minImportance: Double?
    public var metadataFilters: [String: String]?
    public var limit: Int?
    public var sortOrder: SortOrder

    public init(
        ids: Set<MemoryRecordID>? = nil,
        scopes: Set<MemoryScope>? = nil,
        kinds: Set<MemoryKind>? = nil,
        lifecycles: Set<MemoryLifecycle>? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        textSearch: String? = nil,
        minImportance: Double? = nil,
        metadataFilters: [String: String]? = nil,
        limit: Int? = nil,
        sortOrder: SortOrder = .createdAtDescending
    ) {
        self.ids = ids
        self.scopes = scopes
        self.kinds = kinds
        self.lifecycles = lifecycles
        self.startDate = startDate
        self.endDate = endDate
        self.textSearch = textSearch
        self.minImportance = minImportance
        self.metadataFilters = metadataFilters
        self.limit = limit
        self.sortOrder = sortOrder
    }
}

public struct MemoryQueryResult: Sendable, Codable, Equatable {
    public let records: [MemoryRecord]
    public let totalCount: Int
    public let executionDurationNanoseconds: UInt64

    public init(
        records: [MemoryRecord],
        totalCount: Int,
        executionDurationNanoseconds: UInt64 = 0
    ) {
        self.records = records
        self.totalCount = totalCount
        self.executionDurationNanoseconds = executionDurationNanoseconds
    }
}

public enum MemoryRecordValidator {
    public static func validate(_ record: MemoryRecord) throws {
        if record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MemoryError.invalidRecord("Record content cannot be empty")
        }
        if record.importance.isNaN || record.importance.isInfinite || record.importance < 0.0 || record.importance > 1.0 {
            throw MemoryError.invalidRecord("Record importance must be finite and within [0.0, 1.0]")
        }
        if record.version < 1 {
            throw MemoryError.invalidRecord("Record version must be greater than or equal to 1")
        }
    }
}

public enum MemoryQueryValidator {
    public static func validate(_ query: MemoryQuery) throws {
        if let limit = query.limit, limit <= 0 {
            throw MemoryError.invalidQuery("Limit must be greater than zero")
        }
        if let minImp = query.minImportance {
            if minImp.isNaN || minImp.isInfinite || minImp < 0.0 || minImp > 1.0 {
                throw MemoryError.invalidQuery("Query minImportance must be finite and within [0.0, 1.0]")
            }
        }
    }
}

public enum MemoryError: Error, Sendable, Codable, Equatable, CustomStringConvertible {
    case invalidRecord(String)
    case notFound(MemoryRecordID)
    case duplicateID(MemoryRecordID)
    case persistenceFailed(String)
    case corruptRecord(String)
    case schemaMismatch(expected: Int, actual: Int)
    case invalidQuery(String)
    case concurrentConflict(String)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .invalidRecord(let reason):
            return "Invalid memory record: \(reason)"
        case .notFound(let id):
            return "Memory record not found: \(id.rawValue)"
        case .duplicateID(let id):
            return "Duplicate memory ID: \(id.rawValue)"
        case .persistenceFailed(let reason):
            return "Persistence failed: \(reason)"
        case .corruptRecord(let details):
            return "Corrupt record: \(details)"
        case .schemaMismatch(let expected, let actual):
            return "Schema mismatch: expected \(expected), got \(actual)"
        case .invalidQuery(let reason):
            return "Invalid query: \(reason)"
        case .concurrentConflict(let details):
            return "Concurrent conflict: \(details)"
        case .unsupportedVersion(let version):
            return "Unsupported schema version: \(version)"
        }
    }
}

public protocol MemoryStore: Sendable {
    func capture(_ record: MemoryRecord) async throws
    func retrieve(id: MemoryRecordID) async throws -> MemoryRecord?
    func retrieve(kind: MemoryKind, limit: Int) async throws -> [MemoryRecord]
    func update(_ record: MemoryRecord) async throws
    func forget(id: MemoryRecordID, reason: String) async throws
    func query(_ query: MemoryQuery) async throws -> MemoryQueryResult
    func bulkInsert(_ records: [MemoryRecord]) async throws
    func count(scope: MemoryScope?) async throws -> Int
    func clear() async throws
}

public extension MemoryStore {
    func count() async throws -> Int {
        try await count(scope: nil)
    }

    func retrieve(kind: MemoryKind, limit: Int) async throws -> [MemoryRecord] {
        if limit <= 0 {
            throw MemoryError.invalidQuery("Limit must be greater than zero")
        }
        let q = MemoryQuery(kinds: [kind], limit: limit)
        let res = try await query(q)
        return res.records
    }
}

public protocol MemoryExecuting: Sendable {
    func capture(_ record: MemoryRecord) async throws
    func retrieve(id: MemoryRecordID) async throws -> MemoryRecord?
    func retrieve(kind: MemoryKind, limit: Int) async throws -> [MemoryRecord]
    func query(_ query: MemoryQuery) async throws -> MemoryQueryResult
    func update(_ record: MemoryRecord) async throws
    func forget(id: MemoryRecordID, reason: String) async throws
    func count(scope: MemoryScope?) async throws -> Int
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
