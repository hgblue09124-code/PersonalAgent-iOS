import Foundation

public actor PASyncEngine<Local: LocalStore, Cloud: CloudStore>: SyncEngine where Local.Record == Cloud.Record {
    public typealias Record = Local.Record
    public typealias ConflictResolver = @Sendable (Record, Record, ConflictResolution) throws -> Record

    private let localStore: Local
    private let cloudStore: Cloud
    private let queue: PASyncQueue
    private let conflictResolver: ConflictResolver?
    private var pendingConflictsMap: [String: SyncConflict<Record>] = [:]

    public init(
        localStore: Local,
        cloudStore: Cloud,
        queue: PASyncQueue = PASyncQueue(),
        conflictResolver: ConflictResolver? = nil
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.queue = queue
        self.conflictResolver = conflictResolver
    }

    public func enqueueLocalChange(id: String) async throws {
        try await queue.enqueue(id: id)
    }

    public func pendingConflicts() async -> [SyncConflict<Record>] {
        Array(pendingConflictsMap.values)
    }

    public func conflict(for id: String) async -> SyncConflict<Record>? {
        pendingConflictsMap[id]
    }

    public func synchronize() async throws {
        guard await cloudStore.provider.isAvailable else {
            throw CloudStorageError.unavailable("Cloud provider \(cloudStore.provider.identifier) is unavailable")
        }

        let pendingIDs = await queue.allPendingIDs()
        for id in pendingIDs {
            let local = try await localStore.fetch(id: id)
            let remote = try await cloudStore.pull(id: id)

            switch (local, remote) {
            case (.none, .none):
                try await queue.remove(id: id)

            case (.some(let loc), .none):
                try await cloudStore.push(loc)
                try await queue.remove(id: id)

            case (.none, .some(let rem)):
                try await localStore.upsert(rem)
                try await queue.remove(id: id)

            case (.some(let loc), .some(let rem)):
                if loc == rem {
                    try await queue.remove(id: id)
                } else if loc.version == rem.version {
                    // Divergent revisions with same version -> conflict! MUST NOT silently overwrite.
                    let conflict = SyncConflict(local: loc, remote: rem)
                    pendingConflictsMap[id] = conflict
                } else if loc.version > rem.version {
                    try await cloudStore.push(loc)
                    try await queue.remove(id: id)
                } else {
                    try await localStore.upsert(rem)
                    try await queue.remove(id: id)
                }
            }
        }
    }

    public func resolve(_ conflict: SyncConflict<Record>, policy: ConflictResolution) async throws {
        let id = conflict.local.id

        if policy == .requireUser {
            pendingConflictsMap[id] = conflict
            return
        }

        guard let resolver = conflictResolver else {
            throw CloudStorageError.storeFailed("No conflictResolver provided to resolve conflict for record \(id)")
        }

        let resolvedRecord = try resolver(conflict.local, conflict.remote, policy)

        // Write new authoritative revision to local and cloud store
        try await localStore.upsert(resolvedRecord)
        try await cloudStore.push(resolvedRecord)

        pendingConflictsMap.removeValue(forKey: id)
        try await queue.remove(id: id)
    }
}
