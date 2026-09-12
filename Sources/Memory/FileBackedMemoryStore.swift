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

    public init(metadata: MemoryStoreMetadata, records: [MemoryRecord]) {
        self.metadata = metadata
        self.records = records
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
    }

    public func capture(_ record: MemoryRecord) async throws {
        try MemoryRecordValidator.validate(record)
        if index.record(for: record.id) != nil {
            throw MemoryError.duplicateID(record.id)
        }

        let previousIndex = index
        let previousMetadata = metadata

        index.index(record)
        metadata.updatedAt = Date()
        metadata.recordCount = index.count

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
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

        var newAncestors = existing.ancestorVersions
        newAncestors.insert(existing.version)

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
            ancestorVersions: newAncestors
        )

        let previousIndex = index
        let previousMetadata = metadata

        index.index(committedRecord)
        metadata.updatedAt = Date()

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            throw error
        }
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        guard let existing = index.record(for: id) else {
            throw MemoryError.notFound(id)
        }

        var newAncestors = existing.ancestorVersions
        newAncestors.insert(existing.version)

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
            ancestorVersions: newAncestors
        )

        let previousIndex = index
        let previousMetadata = metadata

        index.index(updated)
        metadata.updatedAt = Date()

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
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

        for record in records {
            index.index(record)
        }
        metadata.updatedAt = Date()
        metadata.recordCount = index.count

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
            throw error
        }
    }

    public func count(scope: MemoryScope?) async throws -> Int {
        index.count(scope: scope)
    }

    public func clear() async throws {
        let previousIndex = index
        let previousMetadata = metadata

        index.clear()
        metadata.recordCount = 0
        metadata.updatedAt = Date()

        do {
            try persistToDisk()
        } catch {
            index = previousIndex
            metadata = previousMetadata
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
    ) throws -> (metadata: MemoryStoreMetadata, index: MemoryIndex) {
        let storeURL = directoryURL.appendingPathComponent("store.json")

        var loadedMeta = MemoryStoreMetadata(version: 1)
        var loadedIndex = MemoryIndex()

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
                }

                loadedMeta = snapshot.metadata
            } catch let err as MemoryError {
                throw err
            } catch {
                throw MemoryError.corruptRecord("Corrupt store.json: \(error.localizedDescription)")
            }
        }

        return (loadedMeta, loadedIndex)
    }

    private func persistToDisk() throws {
        let snapshot = MemoryStoreSnapshot(metadata: metadata, records: index.allRecords())
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
            try await update(memRecord)
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

    public func delete(id: String) async throws {
        try await forget(id: MemoryRecordID(rawValue: id), reason: "Deleted via LocalStore interface")
    }
}
