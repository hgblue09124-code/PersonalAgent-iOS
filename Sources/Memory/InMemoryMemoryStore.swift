import Foundation
import PAFoundation

public actor InMemoryMemoryStore: MemoryStore {
    private var index: MemoryIndex

    public init() {
        self.index = MemoryIndex()
    }

    public func capture(_ record: MemoryRecord) async throws {
        if index.record(for: record.id) != nil {
            throw MemoryError.duplicateID(record.id)
        }
        index.index(record)
    }

    public func retrieve(id: MemoryRecordID) async throws -> MemoryRecord? {
        index.record(for: id)
    }

    public func update(_ record: MemoryRecord) async throws {
        guard let existing = index.record(for: record.id) else {
            throw MemoryError.notFound(record.id)
        }
        if existing.version != record.version {
            throw MemoryError.concurrentConflict("Stale update for ID \(record.id.rawValue): existing version \(existing.version), incoming version \(record.version)")
        }
        let committedRecord = MemoryRecord(
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
            version: existing.version + 1
        )
        index.index(committedRecord)
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        guard let existing = index.record(for: id) else {
            throw MemoryError.notFound(id)
        }
        let updated = MemoryRecord(
            id: existing.id,
            kind: existing.kind,
            content: existing.content,
            provenance: existing.provenance,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            scope: existing.scope,
            lifecycle: .deleted,
            importance: existing.importance,
            metadata: existing.metadata,
            version: existing.version + 1
        )
        index.index(updated)
    }

    public func query(_ query: MemoryQuery) async throws -> MemoryQueryResult {
        if let limit = query.limit, limit <= 0 {
            throw MemoryError.invalidQuery("Limit must be greater than zero")
        }
        return index.query(query)
    }

    public func bulkInsert(_ records: [MemoryRecord]) async throws {
        for record in records {
            if index.record(for: record.id) != nil {
                throw MemoryError.duplicateID(record.id)
            }
        }
        for record in records {
            index.index(record)
        }
    }

    public func count(scope: MemoryScope?) async throws -> Int {
        index.count(scope: scope)
    }

    public func clear() async throws {
        index.clear()
    }
}
