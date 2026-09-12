import Testing
import Foundation
import PAFoundation
import PAStorage
import PAMemory
import PAArchitecture

private actor TestDoubleCloudStore<Record: StorageRecord>: CloudStore {
    let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]
    private var shouldFail: Bool = false

    init(provider: any CloudStorageProvider) {
        self.provider = provider
    }

    func setFailureSimulation(_ fail: Bool) {
        self.shouldFail = fail
    }

    func push(_ record: Record) async throws {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is offline")
        }
        if shouldFail {
            throw CloudStorageError.storeFailed("Simulated cloud failure on push")
        }
        records[record.id] = record
    }

    func pull(id: String) async throws -> Record? {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is offline")
        }
        if shouldFail {
            throw CloudStorageError.storeFailed("Simulated cloud failure on pull")
        }
        return records[id]
    }

    func setRecordDirectly(_ record: Record) {
        records[record.id] = record
    }

    func getRecordDirectly(id: String) -> Record? {
        records[id]
    }
}

private func defaultMemoryResolver(local: MemoryStorageRecord, remote: MemoryStorageRecord, policy: ConflictResolution) throws -> MemoryStorageRecord {
    let newVersion = max(local.version, remote.version) + 1
    let newContent: String
    switch policy {
    case .keepLocal:
        newContent = local.record.content
    case .keepRemote:
        newContent = remote.record.content
    case .merge:
        if local.record.content == remote.record.content {
            newContent = local.record.content
        } else {
            newContent = "\(local.record.content)\n\(remote.record.content)"
        }
    case .requireUser:
        throw CloudStorageError.storeFailed("requireUser must be handled prior to resolution")
    }

    var mergedMeta = local.record.metadata
    for (k, v) in remote.record.metadata.storage {
        if mergedMeta[k] == nil {
            mergedMeta[k] = v
        }
    }

    let newMem = MemoryRecord(
        id: local.record.id,
        kind: local.record.kind,
        content: newContent,
        provenance: local.record.provenance,
        createdAt: local.record.createdAt,
        updatedAt: Date(),
        scope: local.record.scope,
        lifecycle: local.record.lifecycle,
        importance: max(local.record.importance, remote.record.importance),
        metadata: mergedMeta,
        version: newVersion
    )
    return MemoryStorageRecord(newMem)
}

@Suite("M5.3 SyncEngine Tests")
struct M5SyncEngineTests {

    // 1. local change enters sync queue
    @Test func testLocalChangeEntersSyncQueue() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "queue-rec-1"),
            kind: .fact,
            content: "Local queue test item",
            provenance: Provenance(source: "user"),
            version: 1
        )
        let storageRecord = MemoryStorageRecord(record)

        try await localStore.upsert(storageRecord)
        try await engine.enqueueLocalChange(id: "queue-rec-1")

        #expect(await queue.count() == 1)
        #expect(await queue.contains(id: "queue-rec-1"))
    }

    // 2. successful local -> cloud synchronization
    @Test func testSuccessfulLocalToCloudSync() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "sync-rec-1"),
            kind: .preference,
            content: "Local change to push to cloud",
            provenance: Provenance(source: "user"),
            version: 1
        )
        let storageRecord = MemoryStorageRecord(record)

        try await localStore.upsert(storageRecord)
        try await engine.enqueueLocalChange(id: "sync-rec-1")

        // Before sync, cloud store has no record
        let cloudBefore = try await cloudStore.pull(id: "sync-rec-1")
        #expect(cloudBefore == nil)

        // Perform sync
        try await engine.synchronize()

        // After sync, cloud store has record and queue is empty
        let cloudAfter = try await cloudStore.pull(id: "sync-rec-1")
        #expect(cloudAfter != nil)
        #expect(cloudAfter?.id == "sync-rec-1")
        #expect(cloudAfter?.record.content == "Local change to push to cloud")
        #expect(await queue.count() == 0)
    }

    // 3. cloud -> local pull without corrupting local state
    @Test func testCloudToLocalPullWithoutCorruptingLocalState() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let remoteRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "pull-rec-1"),
                kind: .semantic,
                content: "Remote record pulled to local",
                provenance: Provenance(source: "agent"),
                version: 2
            )
        )
        await cloudStore.setRecordDirectly(remoteRecord)

        // Enqueue change for pull-rec-1
        try await engine.enqueueLocalChange(id: "pull-rec-1")

        // Before sync, local store has no record
        let localBefore = try await localStore.fetch(id: "pull-rec-1")
        #expect(localBefore == nil)

        // Perform sync
        try await engine.synchronize()

        // Local store now holds remote record, preserving identity and version
        let localAfter = try await localStore.fetch(id: "pull-rec-1")
        #expect(localAfter != nil)
        #expect(localAfter?.id == "pull-rec-1")
        #expect(localAfter?.version == 2)
        #expect(localAfter?.record.content == "Remote record pulled to local")
        #expect(await queue.count() == 0)
    }

    // 4. same-ID divergent revisions produce SyncConflict
    @Test func testSameIDDivergentRevisionsProduceSyncConflict() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let localRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "divergent-rec-1"),
                kind: .fact,
                content: "Local version of content",
                provenance: Provenance(source: "user"),
                version: 2
            )
        )
        let remoteRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "divergent-rec-1"),
                kind: .fact,
                content: "Remote divergent version of content",
                provenance: Provenance(source: "agent"),
                version: 2
            )
        )

        try await localStore.upsert(localRecord)
        await cloudStore.setRecordDirectly(remoteRecord)

        try await engine.enqueueLocalChange(id: "divergent-rec-1")
        try await engine.synchronize()

        let conflicts = await engine.pendingConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.local.id == "divergent-rec-1")
        #expect(conflicts.first?.local.record.content == "Local version of content")
        #expect(conflicts.first?.remote.record.content == "Remote divergent version of content")
    }

    // 5. no silent overwrite
    @Test func testNoSilentOverwrite() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let localRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "no-overwrite-1"),
                kind: .fact,
                content: "Local content stay intact",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        let remoteRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "no-overwrite-1"),
                kind: .fact,
                content: "Remote content stay intact",
                provenance: Provenance(source: "agent"),
                version: 1
            )
        )

        try await localStore.upsert(localRecord)
        await cloudStore.setRecordDirectly(remoteRecord)

        try await engine.enqueueLocalChange(id: "no-overwrite-1")
        try await engine.synchronize()

        // Local and cloud stores MUST retain their respective independent data without silent overwrite
        let localFetched = try await localStore.fetch(id: "no-overwrite-1")
        let cloudFetched = try await cloudStore.pull(id: "no-overwrite-1")

        #expect(localFetched?.record.content == "Local content stay intact")
        #expect(cloudFetched?.record.content == "Remote content stay intact")

        // Conflict is exposed
        let conflict = await engine.conflict(for: "no-overwrite-1")
        #expect(conflict != nil)
    }

    // 6. each conflict policy behaves explicitly
    @Test func testEachConflictPolicyBehavesExplicitly() async throws {
        let policies: [ConflictResolution] = [.keepLocal, .keepRemote, .merge, .requireUser]

        for policy in policies {
            let localStore = InMemoryMemoryStore()
            let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
            let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
            let queue = PASyncQueue()
            let engine = PASyncEngine(
                localStore: localStore,
                cloudStore: cloudStore,
                queue: queue,
                conflictResolver: defaultMemoryResolver
            )

            let localRecord = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: "policy-rec-\(policy.rawValue)"),
                    kind: .preference,
                    content: "Local Policy Value",
                    provenance: Provenance(source: "user"),
                    version: 1
                )
            )
            let remoteRecord = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: "policy-rec-\(policy.rawValue)"),
                    kind: .preference,
                    content: "Remote Policy Value",
                    provenance: Provenance(source: "agent"),
                    version: 1
                )
            )

            let conflict = SyncConflict(local: localRecord, remote: remoteRecord)

            if policy == .requireUser {
                try await engine.resolve(conflict, policy: .requireUser)
                let pending = await engine.pendingConflicts()
                #expect(pending.count == 1)
                #expect(pending.first?.local.id == "policy-rec-requireUser")
            } else {
                try await engine.resolve(conflict, policy: policy)

                let localFetched = try await localStore.fetch(id: "policy-rec-\(policy.rawValue)")
                let cloudFetched = try await cloudStore.pull(id: "policy-rec-\(policy.rawValue)")

                #expect(localFetched != nil)
                #expect(cloudFetched != nil)
                #expect(localFetched == cloudFetched)

                switch policy {
                case .keepLocal:
                    #expect(localFetched?.record.content == "Local Policy Value")
                case .keepRemote:
                    #expect(localFetched?.record.content == "Remote Policy Value")
                case .merge:
                    #expect(localFetched?.record.content == "Local Policy Value\nRemote Policy Value")
                case .requireUser:
                    break
                }
            }
        }
    }

    // 7. successful resolution creates a new revision
    @Test func testSuccessfulResolutionCreatesNewRevision() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(
            localStore: localStore,
            cloudStore: cloudStore,
            queue: queue,
            conflictResolver: defaultMemoryResolver
        )

        let localRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "revision-rec-1"),
                kind: .fact,
                content: "Base local content",
                provenance: Provenance(source: "user"),
                version: 4
            )
        )
        let remoteRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "revision-rec-1"),
                kind: .fact,
                content: "Base remote content",
                provenance: Provenance(source: "agent"),
                version: 4
            )
        )

        let conflict = SyncConflict(local: localRecord, remote: remoteRecord)
        try await engine.resolve(conflict, policy: .keepLocal)

        let resolvedLocal = try await localStore.fetch(id: "revision-rec-1")
        let resolvedRemote = try await cloudStore.pull(id: "revision-rec-1")

        #expect(resolvedLocal?.version == 5)
        #expect(resolvedRemote?.version == 5)
        #expect(resolvedLocal?.id == "revision-rec-1")
        #expect(resolvedLocal?.record.content == "Base local content")
    }

    // 8. repeated/resumed sync is idempotent
    @Test func testRepeatedResumedSyncIsIdempotent() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "idempotent-rec-1"),
                kind: .fact,
                content: "Idempotency check content",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )

        try await localStore.upsert(record)
        try await engine.enqueueLocalChange(id: "idempotent-rec-1")

        // First sync run
        try await engine.synchronize()
        #expect(await queue.count() == 0)

        let cloudRun1 = try await cloudStore.pull(id: "idempotent-rec-1")
        #expect(cloudRun1 == record)

        // Repeat sync run (queue is empty)
        try await engine.synchronize()
        #expect(await queue.count() == 0)

        let cloudRun2 = try await cloudStore.pull(id: "idempotent-rec-1")
        #expect(cloudRun2 == record)
    }

    // 9. cloud failure preserves local state and queued work
    @Test func testCloudFailurePreservesLocalStateAndQueuedWork() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "failing-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let localRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "fail-preserve-1"),
                kind: .fact,
                content: "Local state must not be lost",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )

        try await localStore.upsert(localRecord)
        try await engine.enqueueLocalChange(id: "fail-preserve-1")

        // Enable cloud failure simulation
        await cloudStore.setFailureSimulation(true)

        do {
            try await engine.synchronize()
            Issue.record("Expected synchronize to throw on cloud failure")
        } catch let err as CloudStorageError {
            if case .storeFailed = err {
                // Expected
            } else {
                Issue.record("Expected storeFailed, got \(err)")
            }
        } catch {
            Issue.record("Expected CloudStorageError, got \(error)")
        }

        // Verify local store state remains intact
        let localFetched = try await localStore.fetch(id: "fail-preserve-1")
        #expect(localFetched != nil)
        #expect(localFetched?.id == "fail-preserve-1")
        #expect(localFetched?.record.content == "Local state must not be lost")

        // Verify queue still retains item for resumption
        #expect(await queue.count() == 1)
        #expect(await queue.contains(id: "fail-preserve-1"))
    }

    // 10. M0-M5.2 regression & contract boundaries
    @Test func testM0ToM52RegressionAndSyncEngineBoundaries() throws {
        // PAStorage MUST NOT import PAMemory or PAKernel or PAProviders
        guard let storageImports = ArchitectureManifest.allowedImports["PAStorage"] else {
            Issue.record("PAStorage mapping missing from ArchitectureManifest")
            return
        }
        #expect(!storageImports.contains("PAMemory"))
        #expect(!storageImports.contains("PAKernel"))
        #expect(!storageImports.contains("PAProviders"))

        // Confirm forbidden companion dependencies remain forbidden
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Firebase"))
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Supabase"))
    }
}
