import Foundation

/// State of an item in the sync queue based on retry metadata and queue limits.
public enum PASyncQueueStatus: String, Codable, Sendable, Equatable {
    case pending
    case retrying
    case failed
}

/// Value object representing an entry in the sync queue with retry metadata.
public struct PASyncQueueEntry: Codable, Sendable, Equatable {
    public let id: String
    public var retryCount: Int
    public var lastAttemptAt: Date?
    public var lastError: String?

    public init(
        id: String,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

    public func status(maxRetries: Int) -> PASyncQueueStatus {
        if retryCount >= maxRetries {
            return .failed
        } else if retryCount > 0 {
            return .retrying
        } else {
            return .pending
        }
    }
}

public actor PASyncQueue: Sendable {
    private var pendingIDs: [String] = []
    private var entriesMap: [String: PASyncQueueEntry] = [:]
    private let storageURL: URL?
    public let maxRetries: Int
    public private(set) var corruptionBackupURL: URL?

    public var hasCorruptedStorageBackup: Bool {
        corruptionBackupURL != nil
    }

    private struct PersistedQueue: Codable {
        let pendingIDs: [String]?
        let entries: [PASyncQueueEntry]?
    }

    public init(storageURL: URL? = nil, maxRetries: Int = 3) {
        self.storageURL = storageURL
        self.maxRetries = maxRetries

        if let url = storageURL, FileManager.default.fileExists(atPath: url.path) {
            var loadedSuccessfully = false
            if let data = try? Data(contentsOf: url) {
                let decoder = JSONDecoder()
                if let decoded = try? decoder.decode(PersistedQueue.self, from: data) {
                    if let loadedEntries = decoded.entries, !loadedEntries.isEmpty {
                        var ids: [String] = []
                        var map: [String: PASyncQueueEntry] = [:]
                        for entry in loadedEntries {
                            if map[entry.id] == nil {
                                ids.append(entry.id)
                            }
                            map[entry.id] = entry
                        }
                        self.pendingIDs = ids
                        self.entriesMap = map
                        loadedSuccessfully = true
                    } else if let loadedIDs = decoded.pendingIDs {
                        var ids: [String] = []
                        var map: [String: PASyncQueueEntry] = [:]
                        for id in loadedIDs {
                            if map[id] == nil {
                                ids.append(id)
                                map[id] = PASyncQueueEntry(id: id)
                            }
                        }
                        self.pendingIDs = ids
                        self.entriesMap = map
                        loadedSuccessfully = true
                    }
                }
            }

            if !loadedSuccessfully {
                // Truthful corruption handling: set backupURL ONLY if backup file exists or copyItem succeeds
                let backupURL = url.appendingPathExtension("corrupt")
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    self.corruptionBackupURL = backupURL
                } else {
                    do {
                        try FileManager.default.copyItem(at: url, to: backupURL)
                        self.corruptionBackupURL = backupURL
                    } catch {
                        self.corruptionBackupURL = nil
                    }
                }
            }
        }
    }

    public func enqueue(id: String) async throws {
        if entriesMap[id] == nil {
            pendingIDs.append(id)
            entriesMap[id] = PASyncQueueEntry(id: id)
            try persist()
        }
        // Invariant: If item is already enqueued, do NOT reset its retryCount/metadata
    }

    public func dequeue() async throws -> String? {
        guard !pendingIDs.isEmpty else { return nil }
        let id = pendingIDs.removeFirst()
        entriesMap.removeValue(forKey: id)
        try persist()
        return id
    }

    public func remove(id: String) async throws {
        if entriesMap[id] != nil {
            pendingIDs.removeAll { $0 == id }
            entriesMap.removeValue(forKey: id)
            try persist()
        }
    }

    public func recordFailure(id: String, error: String? = nil) async throws {
        if var entry = entriesMap[id] {
            entry.retryCount += 1
            entry.lastAttemptAt = Date()
            entry.lastError = error
            entriesMap[id] = entry
            try persist()
        }
    }

    public func resetRetryCount(id: String) async throws {
        if var entry = entriesMap[id] {
            entry.retryCount = 0
            entry.lastError = nil
            entriesMap[id] = entry
            try persist()
        }
    }

    public func resetAllRetries() async throws {
        for (id, var entry) in entriesMap {
            entry.retryCount = 0
            entry.lastError = nil
            entriesMap[id] = entry
        }
        try persist()
    }

    public func status(for id: String) async -> PASyncQueueStatus? {
        entriesMap[id]?.status(maxRetries: maxRetries)
    }

    public func isFailed(id: String) async -> Bool {
        await status(for: id) == .failed
    }

    public func contains(id: String) async -> Bool {
        entriesMap[id] != nil
    }

    public func count() async -> Int {
        pendingIDs.count
    }

    public func allPendingIDs() async -> [String] {
        pendingIDs
    }

    public func activePendingIDs() async -> [String] {
        pendingIDs.filter { (entriesMap[$0]?.retryCount ?? 0) < maxRetries }
    }

    public func pendingEntries() async -> [PASyncQueueEntry] {
        pendingIDs.compactMap { entriesMap[$0] }
    }

    public func entry(for id: String) async -> PASyncQueueEntry? {
        entriesMap[id]
    }

    public func retryCount(for id: String) async -> Int {
        entriesMap[id]?.retryCount ?? 0
    }

    public func isMaxRetriesExceeded(id: String) async -> Bool {
        guard let entry = entriesMap[id] else { return false }
        return entry.retryCount >= maxRetries
    }

    public func failedIDs() async -> [String] {
        pendingIDs.filter { (entriesMap[$0]?.retryCount ?? 0) >= maxRetries }
    }

    public func clear() async throws {
        pendingIDs.removeAll()
        entriesMap.removeAll()
        try persist()
    }

    private func persist() throws {
        guard let url = storageURL else { return }
        let payload = PersistedQueue(
            pendingIDs: pendingIDs,
            entries: pendingIDs.compactMap { entriesMap[$0] }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        try data.write(to: url, options: .atomic)
    }
}
