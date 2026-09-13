import Foundation
import PAFoundation
import PAEvents
import PAStorage

public struct MemoryStoreMetadata: Sendable, Codable, Equatable {
    public let version: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var recordCount: Int

    public init(
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordCount: Int = 0
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordCount = recordCount
    }
}

public struct MemoryStoreSnapshot: Sendable, Codable, Equatable {
    public var metadata: MemoryStoreMetadata
    public var records: [MemoryRecord]
    public var historyRecords: [MemoryRecord]?

    public init(metadata: MemoryStoreMetadata, records: [MemoryRecord], historyRecords: [MemoryRecord]? = nil) {
        self.metadata = metadata
        self.records = records
        self.historyRecords = historyRecords
    }
}

public actor FileBackedMemoryStore: MemoryStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let fileWriter: @Sendable (Data, URL) throws -> Void
    private var index: MemoryIndex
    private var metadata: MemoryStoreMetadata
    private var historyMap: [String: [Int: MemoryStorageRecord]] = [:]
    private var knownRevisionTokens: [String: Set<String>] = [:]

    private var storeFileURL: URL {
        directoryURL.appendingPathComponent("store.json")
    }

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        fileWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.fileWriter = fileWriter

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder

        try Self.ensureDirectoryExists(at: directoryURL, fileManager: fileManager)

        let loaded = try Self.loadFromDisk(
            directoryURL: directoryURL,
            fileManager: fileManager,
            decoder: decoder
        )
        self.metadata = loaded.metadata
        self.index = loaded.index
        self.historyMap = loaded.historyMap
        self.knownRevisionTokens = loaded.knownTokens
    }

    public func capture(_ record: MemoryRecord) async throws {
        try MemoryRecordValidator.validate(record)
        if index.record(for: record.id) != nil {
            throw MemoryError.duplicateID(record.id)
        }

        let previousIndex = index
        let previousMetadata = metadata
        let previousHistory = historyMap
        let previousTokens = knownRevisionTokens

        index.index(record)
        metadata.updatedAt = Date()
        metadata.recordCount = index.count
        try recordHistory(MemoryStorageRecord(record))

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            historyMap = previousHistory
            knownRevisionTokens = previousTokens
            throw error
        }
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

        if record.revisionToken != existing.revisionToken,
           knownRevisionTokens[record.id.rawValue]?.contains(record.revisionToken) == true {
            throw MemoryError.corruptRecord("Duplicate revision token \(record.revisionToken) detected for record \(record.id.rawValue)")
        }
        let freshToken = makeFreshRevisionToken(for: record.id.rawValue)

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

        let previousIndex = index
        let previousMetadata = metadata
        let previousHistory = historyMap
        let previousTokens = knownRevisionTokens

        index.index(committedRecord)
        metadata.updatedAt = Date()
        try recordHistory(MemoryStorageRecord(committedRecord))

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            historyMap = previousHistory
            knownRevisionTokens = previousTokens
            throw error
        }
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
            revisionToken: makeFreshRevisionToken(for: existing.id.rawValue),
            parentRevisionToken: existing.revisionToken,
            ancestorRevisionTokens: updatedAncestors
        )

        let previousIndex = index
        let previousMetadata = metadata
        let previousHistory = historyMap
        let previousTokens = knownRevisionTokens

        index.index(updated)
        metadata.updatedAt = Date()
        try recordHistory(MemoryStorageRecord(updated))

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            historyMap = previousHistory
            knownRevisionTokens = previousTokens
            throw error
        }
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

        let previousIndex = index
        let previousMetadata = metadata
        let previousHistory = historyMap
        let previousTokens = knownRevisionTokens

        for record in records {
            index.index(record)
            try recordHistory(MemoryStorageRecord(record))
        }
        metadata.updatedAt = Date()
        metadata.recordCount = index.count

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            historyMap = previousHistory
            knownRevisionTokens = previousTokens
            throw error
        }
    }

    public func count(scope: MemoryScope?) async throws -> Int {
        index.count(scope: scope)
    }

    public func clear() async throws {
        let previousIndex = index
        let previousMetadata = metadata
        let previousHistory = historyMap
        let previousTokens = knownRevisionTokens

        index.clear()
        metadata.recordCount = 0
        metadata.updatedAt = Date()
        historyMap.removeAll()
        knownRevisionTokens.removeAll()

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            historyMap = previousHistory
            knownRevisionTokens = previousTokens
            throw error
        }
    }

    public func reload() throws {
        let loaded = try Self.loadFromDisk(
            directoryURL: directoryURL,
            fileManager: fileManager,
            decoder: jsonDecoder
        )
        self.metadata = loaded.metadata
        self.index = loaded.index
        self.historyMap = loaded.historyMap
        self.knownRevisionTokens = loaded.knownTokens
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

    private func makeFreshRevisionToken(for id: String) -> String {
        var token: String
        repeat {
            token = UUID().uuidString
        } while knownRevisionTokens[id]?.contains(token) == true
        return token
    }

    private static func ensureDirectoryExists(at directoryURL: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw MemoryError.persistenceFailed("Failed to create store directory at \(directoryURL.path): \(error.localizedDescription)")
            }
        }
    }

    private static func loadFromDisk(
        directoryURL: URL,
        fileManager: FileManager,
        decoder: JSONDecoder
    ) throws -> (metadata: MemoryStoreMetadata, index: MemoryIndex, historyMap: [String: [Int: MemoryStorageRecord]], knownTokens: [String: Set<String>]) {
        let storeURL = directoryURL.appendingPathComponent("store.json")

        var loadedMeta = MemoryStoreMetadata(version: 1)
        var loadedIndex = MemoryIndex()
        var loadedHistory: [String: [Int: MemoryStorageRecord]] = [:]
        var loadedTokens: [String: Set<String>] = [:]

        if fileManager.fileExists(atPath: storeURL.path) {
            do {
                let data = try Data(contentsOf: storeURL)
                let snapshot = try decoder.decode(MemoryStoreSnapshot.self, from: data)
                if snapshot.metadata.version != 1 {
                    throw MemoryError.unsupportedVersion(snapshot.metadata.version)
                }
                if snapshot.metadata.recordCount != snapshot.records.count {
                    throw MemoryError.corruptRecord("Snapshot recordCount mismatch: metadata count \(snapshot.metadata.recordCount) != actual records count \(snapshot.records.count)")
                }

                var seenIDs = Set<MemoryRecordID>()
                for record in snapshot.records {
                    try MemoryRecordValidator.validate(record)
                    if seenIDs.contains(record.id) {
                        throw MemoryError.corruptRecord("Duplicate record ID in snapshot: \(record.id.rawValue)")
                    }
                    seenIDs.insert(record.id)
                    loadedIndex.index(record)
                    let storageRec = MemoryStorageRecord(record)
                    let id = storageRec.id
                    let ver = storageRec.version
                    let token = storageRec.revisionToken

                    if loadedTokens[id] == nil { loadedTokens[id] = [] }
                    if loadedTokens[id]?.contains(token) == true {
                        throw MemoryError.corruptRecord("Duplicate revision token \(token) in snapshot for \(id)")
                    }
                    if loadedHistory[id] == nil { loadedHistory[id] = [:] }
                    if loadedHistory[id]?[ver] != nil {
                        throw MemoryError.corruptRecord("Duplicate revision entry for \(id) at version \(ver) in snapshot")
                    }

                    loadedHistory[id]?[ver] = storageRec
                    loadedTokens[id]?.insert(token)
                }

                if let histList = snapshot.historyRecords {
                    for hRec in histList {
                        let storageRec = MemoryStorageRecord(hRec)
                        let id = storageRec.id
                        let ver = storageRec.version
                        let token = storageRec.revisionToken

                        if loadedTokens[id] == nil { loadedTokens[id] = [] }
                        if loadedHistory[id] == nil { loadedHistory[id] = [:] }

                        // If already recorded from active records, verify identity match or throw corruption
                        if let existingVer = loadedHistory[id]?[ver] {
                            if existingVer != storageRec {
                                throw MemoryError.corruptRecord("Conflicting duplicate revision for \(id) at version \(ver) in snapshot")
                            }
                        } else {
                            if loadedTokens[id]?.contains(token) == true {
                                throw MemoryError.corruptRecord("Duplicate revision token \(token) in snapshot for \(id)")
                            }
                            loadedHistory[id]?[ver] = storageRec
                            loadedTokens[id]?.insert(token)
                        }
                    }
                }
                loadedMeta = snapshot.metadata
            } catch let err as MemoryError {
                throw err
            } catch {
                throw MemoryError.corruptRecord("Corrupt store.json: \(error.localizedDescription)")
            }
        }

        return (loadedMeta, loadedIndex, loadedHistory, loadedTokens)
    }

    private func persistToDisk() throws {
        var allHistoryRecords: [MemoryRecord] = []
        for (_, verMap) in historyMap {
            for (_, storageRec) in verMap {
                allHistoryRecords.append(storageRec.record)
            }
        }
        let snapshot = MemoryStoreSnapshot(metadata: metadata, records: index.allRecords(), historyRecords: allHistoryRecords)
        do {
            let data = try jsonEncoder.encode(snapshot)
            try fileWriter(data, storeFileURL)
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.persistenceFailed("Atomic snapshot write failed: \(error.localizedDescription)")
        }
    }
}

extension FileBackedMemoryStore: LocalStore {
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

extension FileBackedMemoryStore: RevisionHistoryStore {
    public func fetchRevision(id: String, version: Int) async throws -> MemoryStorageRecord? {
        guard let versionMap = historyMap[id] else {
            return nil
        }
        return versionMap[version]
    }
}
