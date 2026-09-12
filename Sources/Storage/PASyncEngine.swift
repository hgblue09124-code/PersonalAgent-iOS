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
                } else if rem.isDescendant(of: loc) {
                    // Remote is proven descendant of local -> update local safely
                    try await updateLocalWithRemote(loc: loc, rem: rem)
                    try await queue.remove(id: id)
                } else if loc.isDescendant(of: rem) {
                    // Local is proven descendant of remote -> push local to cloud
                    try await cloudStore.push(loc)
                    try await queue.remove(id: id)
                } else {
                    // Divergence without provable lineage -> produce SyncConflict.
                    // MUST NOT silently overwrite either side!
                    let conflict = SyncConflict(local: loc, remote: rem)
                    pendingConflictsMap[id] = conflict
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
            throw CloudStorageError.storeFailed("Unable to resolve conflict for \(id) without conflictResolver")
        }

        let resolvedBaseRecord = try resolver(conflict.local, conflict.remote, policy)

        let startVersion = conflict.local.version
        let targetVersion = max(conflict.local.version, conflict.remote.version) + 1

        var mergedAncestors = conflict.local.ancestorRevisionTokens
        mergedAncestors.formUnion(conflict.remote.ancestorRevisionTokens)
        mergedAncestors.insert(conflict.local.revisionToken)
        mergedAncestors.insert(conflict.remote.revisionToken)

        // Step-wise advance local store from conflict.local.version up to targetVersion.
        // For each step v from (startVersion + 1) to targetVersion:
        // derive the next parentVersion, revisionToken, parentRevisionToken from the actual committed local revision
        for _ in (startVersion + 1)...targetVersion {
            guard let currentCommittedLocal = try await localStore.fetch(id: id) else {
                throw CloudStorageError.storeFailed("Failed to fetch current local revision during conflict resolution for \(id)")
            }
            let newToken = "\(id)-v\(currentCommittedLocal.version + 1)"
            var stepAncestors = mergedAncestors
            stepAncestors.insert(currentCommittedLocal.revisionToken)
            let stepPrepared = resolvedBaseRecord.updatingVersion(
                currentCommittedLocal.version,
                parentVersion: currentCommittedLocal.version,
                revisionToken: newToken,
                parentRevisionToken: currentCommittedLocal.revisionToken,
                ancestorRevisionTokens: stepAncestors
            )
            try await localStore.upsert(stepPrepared)
        }

        guard let finalCommittedLocal = try await localStore.fetch(id: id) else {
            throw CloudStorageError.storeFailed("Failed to fetch newly committed local record \(id)")
        }

        // Push final authoritative revision to cloud store
        try await cloudStore.push(finalCommittedLocal)

        pendingConflictsMap.removeValue(forKey: id)
        try await queue.remove(id: id)
    }

    private func updateLocalWithRemote(loc: Record, rem: Record) async throws {
        // Local store currently holds loc (version loc.version).
        // Step-wise advance local store deriving each step's parentVersion from the actual committed local revision,
        // so intermediate versions increment sequentially until local store reaches rem.version.
        var currentLocalVersion = loc.version
        while currentLocalVersion < rem.version {
            guard let currentCommitted = try await localStore.fetch(id: loc.id) else {
                throw CloudStorageError.storeFailed("Failed to fetch local record \(loc.id) during remote update")
            }
            var stepAncestors = rem.ancestorRevisionTokens
            stepAncestors.insert(currentCommitted.revisionToken)
            let stepPrepared = rem.updatingVersion(
                currentCommitted.version,
                parentVersion: currentCommitted.version,
                revisionToken: rem.revisionToken,
                parentRevisionToken: currentCommitted.revisionToken,
                ancestorRevisionTokens: stepAncestors
            )
            try await localStore.upsert(stepPrepared)
            currentLocalVersion += 1
        }
    }
}
