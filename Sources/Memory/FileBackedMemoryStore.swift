import Foundation
import PAFoundation
import PAEvents

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

public actor FileBackedMemoryStore: MemoryStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private var index: MemoryIndex
    private var metadata: MemoryStoreMetadata

    private var metadataFileURL: URL {
        directoryURL.appendingPathComponent("metadata.json")
    }

    private var recordsFileURL: URL {
        directoryURL.appendingPathComponent("records.json")
    }

    public init(directoryURL: URL, fileManager: FileManager = .default) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder

        Self.ensureDirectoryExists(at: directoryURL, fileManager: fileManager)

        let loaded = try Self.loadFromDisk(
            directoryURL: directoryURL,
            fileManager: fileManager,
            decoder: decoder
        )
        self.metadata = loaded.metadata
        self.index = loaded.index
    }

    public func capture(_ record: MemoryRecord) async throws {
        if index.record(for: record.id) != nil {
            throw MemoryError.duplicateID(record.id)
        }

        index.index(record)
        metadata.updatedAt = Date()
        metadata.recordCount = index.count

        try persistToDisk()
    }

    public func retrieve(id: MemoryRecordID) async throws -> MemoryRecord? {
        index.record(for: id)
    }

    public func update(_ record: MemoryRecord) async throws {
        guard index.record(for: record.id) != nil else {
            throw MemoryError.notFound(record.id)
        }

        index.index(record)
        metadata.updatedAt = Date()

        try persistToDisk()
    }

    public func forget(id: MemoryRecordID, reason: String) async throws {
        guard let existing = index.record(for: id) else {
            throw MemoryError.notFound(id)
        }

        let updated = existing.updating(lifecycle: .deleted)
        index.index(updated)
        metadata.updatedAt = Date()

        try persistToDisk()
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
        metadata.updatedAt = Date()
        metadata.recordCount = index.count

        try persistToDisk()
    }

    public func count(scope: MemoryScope?) async throws -> Int {
        index.count(scope: scope)
    }

    public func clear() async throws {
        index.clear()
        metadata.recordCount = 0
        metadata.updatedAt = Date()

        try persistToDisk()
    }

    public func reload() throws {
        index.clear()
        let loaded = try Self.loadFromDisk(
            directoryURL: directoryURL,
            fileManager: fileManager,
            decoder: jsonDecoder
        )
        self.metadata = loaded.metadata
        self.index = loaded.index
    }

    private static func ensureDirectoryExists(at directoryURL: URL, fileManager: FileManager) {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private static func loadFromDisk(
        directoryURL: URL,
        fileManager: FileManager,
        decoder: JSONDecoder
    ) throws -> (metadata: MemoryStoreMetadata, index: MemoryIndex) {
        let metaURL = directoryURL.appendingPathComponent("metadata.json")
        let recsURL = directoryURL.appendingPathComponent("records.json")

        var loadedMeta = MemoryStoreMetadata(version: 1)
        var loadedIndex = MemoryIndex()

        if fileManager.fileExists(atPath: metaURL.path) {
            do {
                let metaData = try Data(contentsOf: metaURL)
                loadedMeta = try decoder.decode(MemoryStoreMetadata.self, from: metaData)
                if loadedMeta.version > 1 {
                    throw MemoryError.unsupportedVersion(loadedMeta.version)
                }
            } catch let err as MemoryError {
                throw err
            } catch {
                throw MemoryError.corruptRecord("Corrupt metadata.json: \(error.localizedDescription)")
            }
        }

        if fileManager.fileExists(atPath: recsURL.path) {
            do {
                let recordsData = try Data(contentsOf: recsURL)
                let records = try decoder.decode([MemoryRecord].self, from: recordsData)
                for record in records {
                    loadedIndex.index(record)
                }
            } catch {
                throw MemoryError.corruptRecord("Corrupt records.json: \(error.localizedDescription)")
            }
        }

        return (loadedMeta, loadedIndex)
    }

    private func persistToDisk() throws {
        do {
            let metaData = try jsonEncoder.encode(metadata)
            try metaData.write(to: metadataFileURL, options: .atomic)

            let allRecords = index.allRecords()
            let recordsData = try jsonEncoder.encode(allRecords)
            try recordsData.write(to: recordsFileURL, options: .atomic)
        } catch {
            throw MemoryError.persistenceFailed("Atomic write failed: \(error.localizedDescription)")
        }
    }
}
