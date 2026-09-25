import Foundation

public actor PASyncEngine<Local: LocalStore, Cloud: CloudStore>: SyncEngine where Local.Record == Cloud.Record {
    public typealias Record = Local.Record
    public typealias ConflictResolver = @Sendable (Record, Record, ConflictResolution) throws -> Record

    private let localStore: Local
    private let cloudStore: Cloud
    public let queue: PASyncQueue
    private let conflictResolver: ConflictResolver?
    private let lineageVerifier: (any LineageVerifying<Record>)?
    private var pendingConflictsMap: [String: SyncConflict<Record>] = [:]

    public init(
        localStore: Local,
        cloudStore: Cloud,
        queue: PASyncQueue = PASyncQueue(),
        conflictResolver: ConflictResolver? = nil,
        lineageVerifier: (any LineageVerifying<Record>)? = nil
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.queue = queue
        self.conflictResolver = conflictResolver
        self.lineageVerifier = lineageVerifier
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

        guard await !queue.isCorrupted else {
            let path = queue.storageURL?.path ?? "in-memory"
            throw CloudStorageError.storeFailed("SyncEngine cannot synchronize: PASyncQueue storage at \(path) is corrupt and unrecovered. Call recoverCorruptedStorage() or clear() on queue before synchronizing.")
        }

        let pendingIDs = await queue.allPendingIDs()
        var firstError: Error?

        for id in pendingIDs {
            if await queue.isMaxRetriesExceeded(id: id) {
                continue
            }

            do {
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
                    } else if let verifier = lineageVerifier {
                        let remoteToLocalProof = await verifier.verifyLineage(candidate: rem, ancestor: loc)
                        let localToRemoteProof = await verifier.verifyLineage(candidate: loc, ancestor: rem)

                        if remoteToLocalProof == .provenDescendant {
                            try await updateLocalWithRemote(loc: loc, rem: rem)
                            try await queue.remove(id: id)
                        } else if localToRemoteProof == .provenDescendant {
                            try await cloudStore.push(loc)
                            try await queue.remove(id: id)
                        } else {
                            let conflict = SyncConflict(local: loc, remote: rem)
                            pendingConflictsMap[id] = conflict
                        }
                    } else {
                        // Fallback to direct pair check
                        if rem.isDescendant(of: loc) {
                            try await updateLocalWithRemote(loc: loc, rem: rem)
                            try await queue.remove(id: id)
                        } else if loc.isDescendant(of: rem) {
                            try await cloudStore.push(loc)
                            try await queue.remove(id: id)
                        } else {
                            let conflict = SyncConflict(local: loc, remote: rem)
                            pendingConflictsMap[id] = conflict
                        }
                    }
                }
            } catch {
                try await queue.recordFailure(id: id, error: error.localizedDescription)
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let error = firstError {
            throw error
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

        try await cloudStore.push(finalCommittedLocal)

        pendingConflictsMap.removeValue(forKey: id)
        try await queue.remove(id: id)
    }

    private func updateLocalWithRemote(loc: Record, rem: Record) async throws {
        var currentLocalVersion = loc.version
        while currentLocalVersion < rem.version {
            guard let currentCommitted = try await localStore.fetch(id: loc.id) else {
                throw CloudStorageError.storeFailed("Failed to fetch local record \(loc.id) during remote update")
            }
            let stepToken = "\(loc.id)-v\(currentCommitted.version + 1)"
            var stepAncestors = rem.ancestorRevisionTokens
            stepAncestors.insert(currentCommitted.revisionToken)
            let stepPrepared = rem.updatingVersion(
                currentCommitted.version,
                parentVersion: currentCommitted.version,
                revisionToken: stepToken,
                parentRevisionToken: currentCommitted.revisionToken,
                ancestorRevisionTokens: stepAncestors
            )
            try await localStore.upsert(stepPrepared)
            currentLocalVersion += 1
        }
    }
}
