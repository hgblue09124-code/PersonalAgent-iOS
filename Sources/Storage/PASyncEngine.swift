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

        let targetVersion = max(conflict.local.version, conflict.remote.version) + 1
        var mergedAncestors = conflict.local.ancestorVersions
        mergedAncestors.formUnion(conflict.remote.ancestorVersions)
        mergedAncestors.insert(conflict.local.version)
        mergedAncestors.insert(conflict.remote.version)

        let resolvedRecord = resolvedBaseRecord.updatingVersion(
            targetVersion,
            parentVersion: conflict.local.version,
            ancestorVersions: mergedAncestors
        )

        // Local store currently holds conflict.local (version conflict.local.version).
        // To reach targetVersion in LocalStore (which increments version by +1 on each update),
        // step-wise advance local store from conflict.local.version up to targetVersion - 1,
        // then perform final upsert with targetVersion - 1 so local store arrives at targetVersion.
        var currentLocalVersion = conflict.local.version
        while currentLocalVersion < targetVersion - 1 {
            let nextLocalVersion = currentLocalVersion + 1
            var stepAncestors = mergedAncestors.filter { $0 < currentLocalVersion }
            stepAncestors.insert(currentLocalVersion)
            let stepRecord = resolvedRecord.updatingVersion(
                currentLocalVersion,
                parentVersion: currentLocalVersion - 1 >= 1 ? currentLocalVersion - 1 : nil,
                ancestorVersions: stepAncestors
            )
            try await localStore.upsert(stepRecord)
            currentLocalVersion = nextLocalVersion
        }

        let finalPreparedRecord = resolvedRecord.updatingVersion(
            targetVersion - 1,
            parentVersion: conflict.local.version,
            ancestorVersions: mergedAncestors
        )
        try await localStore.upsert(finalPreparedRecord)

        guard let newlyCommittedLocal = try await localStore.fetch(id: id) else {
            throw CloudStorageError.storeFailed("Failed to fetch newly committed local record \(id)")
        }

        // Push new authoritative revision to cloud store
        try await cloudStore.push(newlyCommittedLocal)

        pendingConflictsMap.removeValue(forKey: id)
        try await queue.remove(id: id)
    }

    private func updateLocalWithRemote(loc: Record, rem: Record) async throws {
        // Local store currently holds loc (version loc.version).
        // To update local store through LocalStore.update() (which requires matching version v and increments to v+1),
        // we step-wise advance local store from loc.version up to rem.version - 1,
        // then perform final upsert with rem's version = rem.version - 1 so local store reaches rem.version.
        var currentLocalVersion = loc.version
        while currentLocalVersion < rem.version - 1 {
            let nextLocalVersion = currentLocalVersion + 1
            var stepAncestors = rem.ancestorVersions.filter { $0 < currentLocalVersion }
            stepAncestors.insert(currentLocalVersion)
            let stepRecord = rem.updatingVersion(
                currentLocalVersion,
                parentVersion: currentLocalVersion - 1 >= 1 ? currentLocalVersion - 1 : nil,
                ancestorVersions: stepAncestors
            )
            try await localStore.upsert(stepRecord)
            currentLocalVersion = nextLocalVersion
        }

        // Final step: upsert with version = rem.version - 1 so local store arrives at rem.version with rem's full content and lineage.
        let finalPreparedRemote = rem.updatingVersion(
            rem.version - 1,
            parentVersion: rem.parentVersion,
            ancestorVersions: rem.ancestorVersions
        )
        try await localStore.upsert(finalPreparedRemote)
    }
}
