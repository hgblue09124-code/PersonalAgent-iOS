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
        guard index.record(for: record.id) != nil else {
            throw MemoryError.notFound(record.id)
        }
        index.index(record)
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        guard let existing = index.record(for: id) else {
            throw MemoryError.notFound(id)
        }
        let updated = existing.updating(lifecycle: .deleted)
        index.index(updated)
    }

    public func query(_ query: MemoryQuery) async throws -> MemoryQueryResult {
        index.query(query)
    }

    public func bulkInsert(_ records: [MemoryRecord]) async throws {
        for record in records {
            if index.record(for: record.id) != nil {
                throw MemoryError.duplicateID(record.id)
            }
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
