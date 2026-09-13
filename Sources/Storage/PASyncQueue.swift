import Foundation

public actor PASyncQueue: Sendable {
    private var pendingIDs: [String] = []
    private var pendingSet: Set<String> = []
    private let storageURL: URL?

    private struct PersistedQueue: Codable {
        let pendingIDs: [String]
    }

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        if let url = storageURL, FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(PersistedQueue.self, from: data) {
                self.pendingIDs = decoded.pendingIDs
                self.pendingSet = Set(decoded.pendingIDs)
            }
        }
    }

    public func enqueue(id: String) async throws {
        if !pendingSet.contains(id) {
            pendingIDs.append(id)
            pendingSet.insert(id)
            try persist()
        }
    }

    public func dequeue() async throws -> String? {
        guard !pendingIDs.isEmpty else { return nil }
        let id = pendingIDs.removeFirst()
        pendingSet.remove(id)
        try persist()
        return id
    }

    public func remove(id: String) async throws {
        if pendingSet.contains(id) {
            pendingIDs.removeAll { $0 == id }
            pendingSet.remove(id)
            try persist()
        }
    }

    public func contains(id: String) async -> Bool {
        pendingSet.contains(id)
    }

    public func count() async -> Int {
        pendingIDs.count
    }

    public func allPendingIDs() async -> [String] {
        pendingIDs
    }

    public func clear() async throws {
        pendingIDs.removeAll()
        pendingSet.removeAll()
        try persist()
    }

    private func persist() throws {
        guard let url = storageURL else { return }
        let payload = PersistedQueue(pendingIDs: pendingIDs)
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
