import Foundation

public actor PASyncEngine<Local: LocalStore, Cloud: CloudStore>: SyncEngine where Local.Record == Cloud.Record {
    public typealias Record = Local.Record
    public typealias ConflictResolver = @Sendable (Record, Record, ConflictResolution) throws -> Record
    public typealias VersionAdapter = @Sendable (Record, Int) -> Record
    public typealias LineageChecker = @Sendable (Record, Record) -> Bool

    private let localStore: Local
    private let cloudStore: Cloud
    private let queue: PASyncQueue
    private let conflictResolver: ConflictResolver?
    private let versionAdapter: VersionAdapter?
    private let lineageChecker: LineageChecker?
    private var pendingConflictsMap: [String: SyncConflict<Record>] = [:]

    public init(
        localStore: Local,
        cloudStore: Cloud,
        queue: PASyncQueue = PASyncQueue(),
        conflictResolver: ConflictResolver? = nil,
        versionAdapter: VersionAdapter? = nil,
        lineageChecker: LineageChecker? = nil
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.queue = queue
        self.conflictResolver = conflictResolver
        self.versionAdapter = versionAdapter
        self.lineageChecker = lineageChecker
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
                } else if hasDeterministicLineage(child: rem, parent: loc) {
                    // Remote is proven descendant of local -> update local safely
                    try await updateLocalWithRemote(loc: loc, rem: rem)
                    try await queue.remove(id: id)
                } else if hasDeterministicLineage(child: loc, parent: rem) {
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

        let currentLocalVersion = conflict.local.version
        let targetVersion = max(conflict.local.version, conflict.remote.version) + 1

        // Step-wise update local store from currentLocalVersion up to targetVersion
        // preserving M5.1 stale-version protection at each step.
        for v in currentLocalVersion..<targetVersion {
            let stepRecord = modifyVersion(resolvedBaseRecord, version: v)
            try await localStore.upsert(stepRecord)
        }

        guard let newlyCommittedLocal = try await localStore.fetch(id: id) else {
            throw CloudStorageError.storeFailed("Failed to fetch newly committed local record \(id)")
        }

        // Push new authoritative revision to cloud store
        try await cloudStore.push(newlyCommittedLocal)

        pendingConflictsMap.removeValue(forKey: id)
        try await queue.remove(id: id)
    }

    private func hasDeterministicLineage(child: Record, parent: Record) -> Bool {
        if let checker = lineageChecker {
            return checker(child, parent)
        }
        return false
    }

    private func updateLocalWithRemote(loc: Record, rem: Record) async throws {
        let locVersion = loc.version
        let remVersion = rem.version

        if remVersion > locVersion {
            for v in locVersion..<remVersion {
                let stepRecord = modifyVersion(rem, version: v)
                try await localStore.upsert(stepRecord)
            }
        } else {
            try await localStore.upsert(rem)
        }
    }

    private func modifyVersion(_ record: Record, version: Int) -> Record {
        if let adapter = versionAdapter {
            return adapter(record, version)
        }
        return record
    }
}
