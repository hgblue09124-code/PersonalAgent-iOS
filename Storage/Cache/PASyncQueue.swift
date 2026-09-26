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
    public let storageURL: URL?
    public let maxRetries: Int
    public private(set) var corruptionBackupURL: URL?
    public private(set) var isCorrupted: Bool = false

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
                // Fail-closed corruption handling: mark queue as corrupted and attempt truthful sidecar backup
                self.isCorrupted = true
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

    public func recoverCorruptedStorage() async throws {
        guard isCorrupted else { return }

        // Attempt data recovery from corruptionBackupURL or storageURL
        var sourceURL = corruptionBackupURL
        if sourceURL == nil || !FileManager.default.fileExists(atPath: sourceURL!.path) {
            sourceURL = storageURL
        }

        if let url = sourceURL, let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) {
            let pattern = #"\"([a-zA-Z0-9_\-]+)\""#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = content as NSString
                let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
                var restoredSet = Set<String>()
                for match in matches {
                    let extracted = nsString.substring(with: match.range(at: 1))
                    let reserved: Set<String> = ["pendingIDs", "entries", "id", "retryCount", "lastError", "lastAttemptAt"]
                    if !reserved.contains(extracted) {
                        if !restoredSet.contains(extracted) {
                            restoredSet.insert(extracted)
                            if entriesMap[extracted] == nil {
                                pendingIDs.append(extracted)
                                entriesMap[extracted] = PASyncQueueEntry(id: extracted)
                            }
                        }
                    }
                }
            }
        }

        self.isCorrupted = false
        try persist()
    }

    public func enqueue(id: String) async throws {
        try checkNotCorrupted()
        if entriesMap[id] == nil {
            pendingIDs.append(id)
            entriesMap[id] = PASyncQueueEntry(id: id)
            try persist()
        }
        // Invariant: If item is already enqueued, do NOT reset its retryCount/metadata
    }

    public func dequeue() async throws -> String? {
        try checkNotCorrupted()
        guard !pendingIDs.isEmpty else { return nil }
        let id = pendingIDs.removeFirst()
        entriesMap.removeValue(forKey: id)
        try persist()
        return id
    }

    public func remove(id: String) async throws {
        try checkNotCorrupted()
        if entriesMap[id] != nil {
            pendingIDs.removeAll { $0 == id }
            entriesMap.removeValue(forKey: id)
            try persist()
        }
    }

    public func recordFailure(id: String, error: String? = nil) async throws {
        try checkNotCorrupted()
        if var entry = entriesMap[id] {
            entry.retryCount += 1
            entry.lastAttemptAt = Date()
            entry.lastError = error
            entriesMap[id] = entry
            try persist()
        }
    }

    public func resetRetryCount(id: String) async throws {
        try checkNotCorrupted()
        if var entry = entriesMap[id] {
            entry.retryCount = 0
            entry.lastError = nil
            entriesMap[id] = entry
            try persist()
        }
    }

    public func resetAllRetries() async throws {
        try checkNotCorrupted()
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
        self.isCorrupted = false
        pendingIDs.removeAll()
        entriesMap.removeAll()
        try persist()
    }

    private func checkNotCorrupted() throws {
        if isCorrupted {
            let path = storageURL?.path ?? "in-memory"
            throw CloudStorageError.storeFailed("PASyncQueue storage at \(path) is corrupt and unrecovered. Call recoverCorruptedStorage() or clear() before performing queue operations.")
        }
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
