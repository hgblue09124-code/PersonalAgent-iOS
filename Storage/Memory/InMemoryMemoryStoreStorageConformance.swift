import PAMemory
import PAStorageModels

extension InMemoryMemoryStore: LocalStore {
    public typealias Record = MemoryStorageRecord

    public func upsert(_ record: MemoryStorageRecord) async throws {
        let memRecord = record.record
        if try await retrieve(id: memRecord.id) != nil {
            try await update(memRecord)
        } else {
            try await capture(memRecord)
        }
    }

    public func fetch(id: String) async throws -> MemoryStorageRecord? {
        guard let record = try await retrieve(id: MemoryRecordID(rawValue: id)) else {
            return nil
        }
        return MemoryStorageRecord(record)
    }

    public func forget(id: String) async throws {
        try await forget(id: MemoryRecordID(rawValue: id), reason: "Forgotten via LocalStore interface")
    }
}

extension InMemoryMemoryStore: RevisionHistoryStore {
    public func fetchRevision(id: String, version: Int) async throws -> MemoryStorageRecord? {
        guard let record = await revisionRecord(id: id, version: version) else {
            return nil
        }
        return MemoryStorageRecord(record)
    }
}
