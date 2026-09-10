import Foundation
import PAFoundation
import PAEvents

public actor MemoryRuntime: MemoryExecuting, Sendable {
    public let store: any MemoryStore
    public let eventLog: (any EventLog)?
    public let traceID: TraceID

    public init(
        store: any MemoryStore,
        eventLog: (any EventLog)? = nil,
        traceID: TraceID = TraceID()
    ) {
        self.store = store
        self.eventLog = eventLog
        self.traceID = traceID
    }

    public func validate(_ record: MemoryRecord) throws {
        if record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MemoryError.invalidRecord("Record content cannot be empty")
        }
    }

    public func capture(_ record: MemoryRecord) async throws {
        try validate(record)
        try await store.capture(record)
        await logEvent(
            kind: .memoryCaptured,
            payload: [
                "id": record.id.rawValue,
                "kind": record.kind.rawValue,
                "scope": record.scope.rawValue
            ]
        )
    }

    public func retrieve(id: MemoryRecordID) async throws -> MemoryRecord? {
        try await store.retrieve(id: id)
    }

    public func retrieve(kind: MemoryKind, limit: Int) async throws -> [MemoryRecord] {
        if limit <= 0 {
            throw MemoryError.invalidQuery("Limit must be greater than zero")
        }
        let q = MemoryQuery(kinds: [kind], limit: limit)
        let res = try await query(q)
        return res.records
    }

    public func update(_ record: MemoryRecord) async throws {
        try validate(record)
        try await store.update(record)
        await logEvent(
            kind: .memoryUpdated,
            payload: [
                "id": record.id.rawValue,
                "version": String(record.version)
            ]
        )
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        try await store.forget(id: id, reason: reason)
        await logEvent(
            kind: .memoryForgotten,
            payload: [
                "id": id.rawValue,
                "reason": reason
            ]
        )
    }

    public func query(_ query: MemoryQuery) async throws -> MemoryQueryResult {
        if let limit = query.limit, limit <= 0 {
            throw MemoryError.invalidQuery("Limit must be greater than zero")
        }
        let res = try await store.query(query)
        await logEvent(
            kind: .memoryQueried,
            payload: [
                "resultCount": String(res.records.count),
                "totalCount": String(res.totalCount)
            ]
        )
        return res
    }

    public func bulkInsert(_ records: [MemoryRecord]) async throws {
        for record in records {
            try validate(record)
        }
        try await store.bulkInsert(records)
        await logEvent(
            kind: .memoryCaptured,
            payload: [
                "bulk": "true",
                "count": String(records.count)
            ]
        )
    }

    public func count(scope: MemoryScope? = nil) async throws -> Int {
        try await store.count(scope: scope)
    }

    public func clear() async throws {
        try await store.clear()
    }

    private func logEvent(kind: ExecutionEventKind, payload: [String: String]) async {
        guard let eventLog else { return }
        let event = ExecutionEvent(traceID: traceID, kind: kind, payload: payload)
        try? await eventLog.append(event)
    }
}
