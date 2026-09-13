import Foundation
import PAFoundation
import PAStorage

public actor InMemoryMemoryStore: MemoryStore {
    private var index: MemoryIndex
    private var historyMap: [String: [Int: MemoryStorageRecord]] = [:]
    private var knownRevisionTokens: [String: Set<String>] = [:]

    public init() {
        self.index = MemoryIndex()
    }

    public func capture(_ record: MemoryRecord) async throws {
        try MemoryRecordValidator.validate(record)
        if index.record(for: record.id) != nil {
            throw MemoryError.duplicateID(record.id)
        }
        let storageRec = MemoryStorageRecord(record)
        try recordHistory(storageRec)
        index.index(record)
    }

    public func retrieve(id: MemoryRecordID) async throws -> MemoryRecord? {
        index.record(for: id)
    }

    public func update(_ record: MemoryRecord) async throws {
        try MemoryRecordValidator.validate(record)
        guard let existing = index.record(for: record.id) else {
            throw MemoryError.notFound(record.id)
        }
        if existing.version != record.version {
            throw MemoryError.concurrentConflict("Stale update for ID \(record.id.rawValue): existing version \(existing.version), incoming version \(record.version)")
        }
        var updatedAncestors = existing.ancestorRevisionTokens
        updatedAncestors.insert(existing.revisionToken)
        updatedAncestors.formUnion(record.ancestorRevisionTokens)

        let freshToken: String
        if record.revisionToken.isEmpty || record.revisionToken == existing.revisionToken || record.revisionToken == "\(record.id.rawValue)-v\(existing.version)" {
            freshToken = "\(record.id.rawValue)-v\(existing.version + 1)"
        } else {
            freshToken = record.revisionToken
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
            version: existing.version + 1,
            parentVersion: existing.version,
            revisionToken: freshToken,
            parentRevisionToken: existing.revisionToken,
            ancestorRevisionTokens: updatedAncestors
        )
        let storageRec = MemoryStorageRecord(committedRecord)
        try recordHistory(storageRec)
        index.index(committedRecord)
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        guard let existing = index.record(for: id) else {
            throw MemoryError.notFound(id)
        }
        var updatedAncestors = existing.ancestorRevisionTokens
        updatedAncestors.insert(existing.revisionToken)

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
            version: existing.version + 1,
            parentVersion: existing.version,
            revisionToken: "\(existing.id.rawValue)-v\(existing.version + 1)",
            parentRevisionToken: existing.revisionToken,
            ancestorRevisionTokens: updatedAncestors
        )
        let storageRec = MemoryStorageRecord(updated)
        try recordHistory(storageRec)
        index.index(updated)
    }

    public func query(_ query: MemoryQuery) async throws -> MemoryQueryResult {
        try MemoryQueryValidator.validate(query)
        return index.query(query)
    }

    public func bulkInsert(_ records: [MemoryRecord]) async throws {
        var seenIDs = Set<MemoryRecordID>()
        for record in records {
            try MemoryRecordValidator.validate(record)
            if seenIDs.contains(record.id) {
                throw MemoryError.duplicateID(record.id)
            }
            seenIDs.insert(record.id)
            if index.record(for: record.id) != nil {
                throw MemoryError.duplicateID(record.id)
            }
        }
        for record in records {
            let storageRec = MemoryStorageRecord(record)
            try recordHistory(storageRec)
            index.index(record)
        }
    }

    public func count(scope: MemoryScope?) async throws -> Int {
        index.count(scope: scope)
    }

    public func clear() async throws {
        index.clear()
        historyMap.removeAll()
        knownRevisionTokens.removeAll()
    }

    private func recordHistory(_ storageRecord: MemoryStorageRecord) throws {
        let id = storageRecord.id
        let ver = storageRecord.version
        let token = storageRecord.revisionToken

        guard !token.isEmpty else {
            throw MemoryError.corruptRecord("Revision token cannot be empty")
        }

        if knownRevisionTokens[id] == nil {
            knownRevisionTokens[id] = []
        }

        if knownRevisionTokens[id]?.contains(token) == true {
            throw MemoryError.corruptRecord("Duplicate revision token \(token) detected for record \(id)")
        }

        if historyMap[id] == nil {
            historyMap[id] = [:]
        }

        if historyMap[id]?[ver] != nil {
            throw MemoryError.corruptRecord("Duplicate revision history entry detected for \(id) at version \(ver)")
        }

        historyMap[id]?[ver] = storageRecord
        knownRevisionTokens[id]?.insert(token)
    }
}

extension InMemoryMemoryStore: LocalStore {
    public typealias Record = MemoryStorageRecord

    public func upsert(_ record: MemoryStorageRecord) async throws {
        let memRecord = record.record
        if index.record(for: memRecord.id) != nil {
            let preparedRecord = MemoryRecord(
                id: memRecord.id,
                kind: memRecord.kind,
                content: memRecord.content,
                provenance: memRecord.provenance,
                createdAt: memRecord.createdAt,
                updatedAt: memRecord.updatedAt,
                scope: memRecord.scope,
                lifecycle: memRecord.lifecycle,
                importance: memRecord.importance,
                metadata: memRecord.metadata,
                version: memRecord.version,
                parentVersion: memRecord.parentVersion,
                revisionToken: memRecord.revisionToken,
                parentRevisionToken: memRecord.parentRevisionToken,
                ancestorRevisionTokens: memRecord.ancestorRevisionTokens
            )
            try await update(preparedRecord)
        } else {
            try await capture(memRecord)
        }
    }

    public func fetch(id: String) async throws -> MemoryStorageRecord? {
        if let memRecord = try await retrieve(id: MemoryRecordID(rawValue: id)) {
            return MemoryStorageRecord(memRecord)
        }
        return nil
    }

    public func forget(id: String) async throws {
        try await forget(id: MemoryRecordID(rawValue: id), reason: "Forgotten via LocalStore interface")
    }
}

extension InMemoryMemoryStore: RevisionHistoryStore {
    public func fetchRevision(id: String, version: Int) async throws -> MemoryStorageRecord? {
        guard let versionMap = historyMap[id] else {
            return nil
        }
        return versionMap[version]
    }
}
