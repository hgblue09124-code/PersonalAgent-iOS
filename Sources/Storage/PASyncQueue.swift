import Foundation

public actor PASyncQueue: Sendable {
    private var pendingIDs: [String] = []
    private var pendingSet: Set<String> = []
    private let storageURL: URL?

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        if let storageURL = storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            if let data = try? Data(contentsOf: storageURL),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                self.pendingIDs = decoded
                self.pendingSet = Set(decoded)
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
            pendingSet.remove(id)
            pendingIDs.removeAll { $0 == id }
            try persist()
        }
    }

    public func allPendingIDs() async -> [String] {
        return pendingIDs
    }

    public func contains(id: String) async -> Bool {
        return pendingSet.contains(id)
    }

    public func count() async -> Int {
        return pendingIDs.count
    }

    private func persist() throws {
        guard let storageURL = storageURL else { return }
        let parentDir = storageURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(pendingIDs)
        try data.write(to: storageURL, options: .atomic)
    }
}
