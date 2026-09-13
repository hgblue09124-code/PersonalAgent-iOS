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
        version: local.version,
        parentVersion: local.parentVersion,
        revisionToken: local.revisionToken,
        parentRevisionToken: local.parentRevisionToken,
        ancestorRevisionTokens: local.ancestorRevisionTokens.union(remote.ancestorRevisionTokens)
    )
    return MemoryStorageRecord(newMem)
}

@Suite("M5.3 SyncEngine Tests")
struct M5SyncEngineTests {

    // 1. Direct Parent
    @Test func test1_DirectParent() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )
        let v2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-1"),
                kind: .fact,
                content: "V2 content",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-v2",
                parentRevisionToken: "token-v1"
            )
        )

        try await localStore.upsert(v1)

        let result = await verifier.verifyLineage(candidate: v2, ancestor: v1)
        #expect(result == .provenDescendant)
        #expect(v2.isDescendant(of: v1) == true)
    }

    // 2. Valid Multi-Generation
    @Test func test2_ValidMultiGeneration() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-multi-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )

        try await localStore.upsert(v1)

        // Perform sequential updates via store to advance history properly with fresh tokens
        let v1Fetched = try await localStore.fetch(id: "rec-multi-1")
        #expect(v1Fetched != nil)

        let v2Record = v1Fetched!.record.updating(content: "V2 content", revisionToken: "token-v2")
        try await localStore.upsert(MemoryStorageRecord(v2Record))

        let v2Fetched = try await localStore.fetch(id: "rec-multi-1")
        #expect(v2Fetched != nil)

        let v3Record = v2Fetched!.record.updating(content: "V3 content", revisionToken: "token-v3")
        try await localStore.upsert(MemoryStorageRecord(v3Record))

        let v3Fetched = try await localStore.fetch(id: "rec-multi-1")
        #expect(v3Fetched != nil)

        let result = await verifier.verifyLineage(candidate: v3Fetched!, ancestor: v1)
        #expect(result == .provenDescendant)
    }

    // 3. Missing History
    @Test func test3_MissingHistory() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-missing-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )
        let v4 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-missing-1"),
                kind: .fact,
                content: "V4 content without v2/v3 in history",
                provenance: Provenance(source: "agent"),
                version: 4,
                parentVersion: 3,
                revisionToken: "token-v4",
                parentRevisionToken: "token-v3"
            )
        )

        try await localStore.upsert(v1)

        let result = await verifier.verifyLineage(candidate: v4, ancestor: v1)
        #expect(result == .unprovenGap(requiredVersionRange: 2...3))
    }

    // 4. Forged Ancestor Set
    @Test func test4_ForgedAncestorSet() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-forged-set-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "target-v1-token"
            )
        )
        let v5Forged = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-forged-set-1"),
                kind: .fact,
                content: "Forged V5 content carrying target token in set",
                provenance: Provenance(source: "agent"),
                version: 5,
                parentVersion: 4,
                revisionToken: "token-v5",
                parentRevisionToken: "token-v4-fake",
                ancestorRevisionTokens: ["target-v1-token", "token-v4-fake"]
            )
        )

        try await localStore.upsert(v1)

        // Verifier walks history, finds missing v2/v3/v4 records and ignores self-declared ancestorRevisionTokens
        let result = await verifier.verifyLineage(candidate: v5Forged, ancestor: v1)
        #expect(result == .unprovenGap(requiredVersionRange: 2...4))
    }

    // 5. Forged Parent Token
    @Test func test5_ForgedParentToken() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-forged-pToken-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "target-v1-token"
            )
        )
        let v2Forged = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-forged-pToken-1"),
                kind: .fact,
                content: "V2 claiming non-existent parent token",
                provenance: Provenance(source: "agent"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-v2",
                parentRevisionToken: "fake-parent-token"
            )
        )

        try await localStore.upsert(v1)

        let result = await verifier.verifyLineage(candidate: v2Forged, ancestor: v1)
        #expect(result == .notDescendant)
    }

    // 6. Broken Intermediate Link
    @Test func test6_BrokenIntermediateLink() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-broken-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )

        try await localStore.upsert(v1)

        // Update v1 -> v2 via store with fresh token "token-v2-real"
        let v1Fetched = try await localStore.fetch(id: "rec-broken-1")
        #expect(v1Fetched != nil)

        let v2Record = v1Fetched!.record.updating(content: "V2 content", revisionToken: "token-v2-real")
        try await localStore.upsert(MemoryStorageRecord(v2Record))

        let v3Broken = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-broken-1"),
                kind: .fact,
                content: "V3 content pointing to wrong parent token",
                provenance: Provenance(source: "agent"),
                version: 3,
                parentVersion: 2,
                revisionToken: "token-v3",
                parentRevisionToken: "token-v2-wrong"
            )
        )

        let result = await verifier.verifyLineage(candidate: v3Broken, ancestor: v1)
        #expect(result == .notDescendant)
    }

    // 7. Cyclic Lineage
    @Test func test7_CyclicLineage() async throws {
        let localStore = InMemoryMemoryStore()
        let verifier = DefaultLineageVerifier(historyStore: localStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-cyclic-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )
        let v2Cyclic = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-cyclic-1"),
                kind: .fact,
                content: "V2 content with cyclic token",
                provenance: Provenance(source: "agent"),
                version: 2,
                parentVersion: 1,
                revisionToken: "cyclic-token",
                parentRevisionToken: "cyclic-token"
            )
        )

        try await localStore.upsert(v1)

        let result = await verifier.verifyLineage(candidate: v2Cyclic, ancestor: v1)
        #expect(result == .corruptHistory("Cyclic revision token: cyclic-token"))
    }

    // 8. Duplicate Revisions
    @Test func test8_DuplicateRevisions() async throws {
        // Test double simulating store corruption where history returns error on duplicate
        struct CorruptHistoryStore: RevisionHistoryStore {
            typealias Record = MemoryStorageRecord
            func fetchRevision(id: String, version: Int) async throws -> MemoryStorageRecord? {
                if version == 2 {
                    throw CloudStorageError.conflict("Duplicate revisions detected at version 2")
                }
                return nil
            }
        }

        let corruptStore = CorruptHistoryStore()
        let verifier = DefaultLineageVerifier(historyStore: corruptStore)

        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-dup-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )
        let v3 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-dup-1"),
                kind: .fact,
                content: "V3 content",
                provenance: Provenance(source: "agent"),
                version: 3,
                parentVersion: 2,
                revisionToken: "token-v3",
                parentRevisionToken: "token-v2"
            )
        )

        let result = await verifier.verifyLineage(candidate: v3, ancestor: v1)
        if case .corruptHistory = result {
            // Expected fail closed
        } else {
            Issue.record("Expected corruptHistory, got \(result)")
        }
    }

    // 9. Shared Revision Tokens
    @Test func test9_SharedRevisionTokens() async throws {
        let localStore = InMemoryMemoryStore()

        let v1Shared = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-shared-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )

        try await localStore.upsert(v1Shared)

        // Advance v1 -> v2 with fresh token
        let fetched1 = try await localStore.fetch(id: "rec-shared-1")
        #expect(fetched1 != nil)

        let v2Record = fetched1!.record.updating(content: "V2 content", revisionToken: "token-v2")
        try await localStore.upsert(MemoryStorageRecord(v2Record))

        // Attempting update v2 -> v3 explicitly reusing v1's token "token-v1"
        let fetched2 = try await localStore.fetch(id: "rec-shared-1")
        #expect(fetched2 != nil)

        let v3ReusedToken = fetched2!.record.updating(
            content: "V3 reusing v1 token",
            revisionToken: "token-v1"
        )

        do {
            try await localStore.upsert(MemoryStorageRecord(v3ReusedToken))
            Issue.record("Expected upsert with duplicate revisionToken to fail")
        } catch let err as MemoryError {
            if case .corruptRecord = err {
                // Expected fail closed as corruption
            } else {
                Issue.record("Expected corruptRecord, got \(err)")
            }
        } catch {
            Issue.record("Expected MemoryError, got \(error)")
        }
    }

    // 10. Version-gap Resolution v4 -> v5 -> v6 -> v7
    @Test func test10_VersionGapResolutionV4ToV7() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let verifier = DefaultLineageVerifier(historyStore: localStore)
        let engine = PASyncEngine(
            localStore: localStore,
            cloudStore: cloudStore,
            queue: queue,
            conflictResolver: defaultMemoryResolver,
            lineageVerifier: verifier
        )

        let localV4 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "vgap-rec-1"),
                kind: .fact,
                content: "Local v4 content",
                provenance: Provenance(source: "user"),
                version: 4,
                parentVersion: 3
            )
        )

        let remoteV6 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "vgap-rec-1"),
                kind: .fact,
                content: "Remote v6 content",
                provenance: Provenance(source: "agent"),
                version: 6,
                parentVersion: 5
            )
        )

        try await localStore.upsert(localV4)
        await cloudStore.setRecordDirectly(remoteV6)

        let conflict = SyncConflict(local: localV4, remote: remoteV6)
        try await engine.resolve(conflict, policy: .keepLocal)

        let localFinal = try await localStore.fetch(id: "vgap-rec-1")
        let cloudFinal = try await cloudStore.pull(id: "vgap-rec-1")

        #expect(localFinal?.id == "vgap-rec-1")
        #expect(localFinal?.version == 7)
        #expect(localFinal?.parentVersion == 6, "v7 MUST have immediate parent version 6")
        #expect(cloudFinal?.version == 7)
        #expect(cloudFinal?.parentVersion == 6)
        #expect(cloudFinal?.record.content == "Local v4 content")
    }

    // 11. Local change enters sync queue
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

    // 12. Cloud failure preserves local state and queued work
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

        let localFetched = try await localStore.fetch(id: "fail-preserve-1")
        #expect(localFetched != nil)
        #expect(localFetched?.id == "fail-preserve-1")
        #expect(localFetched?.record.content == "Local state must not be lost")

        #expect(await queue.count() == 1)
        #expect(await queue.contains(id: "fail-preserve-1"))
    }

    // 13. Durable queue recovery tests
    @Test func testDurableQueueSurvivesPersistenceAndReload() async throws {
        let tempQueueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5QueuePersistence_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempQueueDir) }

        let queueFileURL = tempQueueDir.appendingPathComponent("queue.json")

        let queue1 = PASyncQueue(storageURL: queueFileURL)
        try await queue1.enqueue(id: "durable-1")
        try await queue1.enqueue(id: "durable-2")

        #expect(await queue1.count() == 2)

        let queue2 = PASyncQueue(storageURL: queueFileURL)
        #expect(await queue2.count() == 2)
        #expect(await queue2.contains(id: "durable-1"))
        #expect(await queue2.contains(id: "durable-2"))

        let dequeued = try await queue2.dequeue()
        #expect(dequeued == "durable-1")

        let queue3 = PASyncQueue(storageURL: queueFileURL)
        #expect(await queue3.count() == 1)
        #expect(await queue3.contains(id: "durable-2"))
    }

    // 14. M0-M5.2 regression & contract boundaries
    @Test func testM0ToM52RegressionAndSyncEngineBoundaries() throws {
        guard let storageImports = ArchitectureManifest.allowedImports["PAStorage"] else {
            Issue.record("PAStorage mapping missing from ArchitectureManifest")
            return
        }
        #expect(!storageImports.contains("PAMemory"))
        #expect(!storageImports.contains("PAKernel"))
        #expect(!storageImports.contains("PAProviders"))

        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Firebase"))
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Supabase"))
    }

    // 15. Restart and Interruption Recovery
    @Test func test15_RestartAndInterruptionRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5RestartRecovery_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let queueFileURL = tempDir.appendingPathComponent("queue.json")

        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "restart-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)

        let queue1 = PASyncQueue(storageURL: queueFileURL)
        let engine1 = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue1)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "restart-rec-1"),
                kind: .fact,
                content: "Record surviving process restart",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(record)
        try await engine1.enqueueLocalChange(id: "restart-rec-1")

        // Simulate crash / restart by dropping engine1 & queue1 and reloading queue2 from disk
        let queue2 = PASyncQueue(storageURL: queueFileURL)
        let engine2 = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue2)

        #expect(await engine2.queue.contains(id: "restart-rec-1"))
        #expect(await engine2.queue.count() == 1)

        try await engine2.synchronize()

        #expect(await engine2.queue.count() == 0)
        let cloudRecord = try await cloudStore.pull(id: "restart-rec-1")
        #expect(cloudRecord?.record.content == "Record surviving process restart")
    }

    // 16. Failed Push/Pull Retry Tracking
    @Test func test16_FailedPushPullRetryTracking() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "retry-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "retry-rec-1"),
                kind: .fact,
                content: "Retry tracking record",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(record)
        try await engine.enqueueLocalChange(id: "retry-rec-1")

        await cloudStore.setFailureSimulation(true)

        do {
            try await engine.synchronize()
            Issue.record("Expected failure during cloud push")
        } catch {
            // Expected
        }

        #expect(await queue.retryCount(for: "retry-rec-1") == 1)
        let entry = await queue.entry(for: "retry-rec-1")
        #expect(entry?.lastError != nil)

        // Clear failure simulation and retry sync
        await cloudStore.setFailureSimulation(false)
        try await engine.synchronize()

        #expect(await queue.count() == 0)
        let pushed = try await cloudStore.pull(id: "retry-rec-1")
        #expect(pushed != nil)
    }

    // 17. Bounded Retry Behavior and Reset
    @Test func test17_BoundedRetryBehaviorAndReset() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "bounded-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue(maxRetries: 2)
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "bounded-rec-1"),
                kind: .fact,
                content: "Bounded retry record",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(record)
        try await engine.enqueueLocalChange(id: "bounded-rec-1")

        await cloudStore.setFailureSimulation(true)

        // Attempt 1 -> fails, retryCount = 1
        try? await engine.synchronize()
        #expect(await queue.retryCount(for: "bounded-rec-1") == 1)

        // Attempt 2 -> fails, retryCount = 2
        try? await engine.synchronize()
        #expect(await queue.retryCount(for: "bounded-rec-1") == 2)
        #expect(await queue.isMaxRetriesExceeded(id: "bounded-rec-1") == true)
        #expect(await queue.failedIDs() == ["bounded-rec-1"])

        // Attempt 3 -> skipped because max retries reached, no error thrown
        try await engine.synchronize()
        #expect(await queue.count() == 1)

        // Reset retries and allow sync to succeed
        try await queue.resetAllRetries()
        #expect(await queue.retryCount(for: "bounded-rec-1") == 0)
        await cloudStore.setFailureSimulation(false)

        try await engine.synchronize()
        #expect(await queue.count() == 0)
    }

    // 18. Offline Recovery
    @Test func test18_OfflineRecovery() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "offline-cloud", isAvailable: false)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "offline-rec-1"),
                kind: .fact,
                content: "Offline recovery content",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(record)
        try await engine.enqueueLocalChange(id: "offline-rec-1")

        do {
            try await engine.synchronize()
            Issue.record("Expected failure when provider is offline")
        } catch let err as CloudStorageError {
            if case .unavailable = err {
                // Expected
            } else {
                Issue.record("Expected unavailable, got \(err)")
            }
        }

        // Local state and queue item remain preserved
        #expect(await queue.count() == 1)
        #expect(try await localStore.fetch(id: "offline-rec-1") != nil)

        // Provider comes back online
        provider.setAvailable(true)
        try await engine.synchronize()

        #expect(await queue.count() == 0)
        let remoteRecord = try await cloudStore.pull(id: "offline-rec-1")
        #expect(remoteRecord?.record.content == "Offline recovery content")
    }

    // 19. Corrupt Queue File Handling and Atomicity
    @Test func test19_CorruptQueueFileHandlingAndAtomicity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5CorruptQueue_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let queueFileURL = tempDir.appendingPathComponent("queue.json")

        // Write corrupt garbage data
        let garbageData = "NOT_VALID_JSON_GARBAGE_###".data(using: .utf8)!
        try garbageData.write(to: queueFileURL)

        // Instantiating queue must gracefully fall back to empty state without throwing or crashing
        let queue = PASyncQueue(storageURL: queueFileURL)
        #expect(await queue.count() == 0)

        // Enqueueing persists new valid payload atomically
        try await queue.enqueue(id: "atomic-rec-1")
        #expect(await queue.count() == 1)

        let reloadedQueue = PASyncQueue(storageURL: queueFileURL)
        #expect(await reloadedQueue.count() == 1)
        #expect(await reloadedQueue.contains(id: "atomic-rec-1"))
    }

    // 20. Idempotent Sync Retry (No duplicate records or artificial version increments)
    @Test func test20_IdempotentSyncRetryNoArtificialVersionIncrements() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "idempotent-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "idempotent-rec-1"),
                kind: .fact,
                content: "Idempotent sync content",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-v2",
                parentRevisionToken: "token-v1"
            )
        )

        try await localStore.upsert(record)
        await cloudStore.setRecordDirectly(record)

        try await engine.enqueueLocalChange(id: "idempotent-rec-1")
        #expect(await queue.count() == 1)

        // First sync pass: detects loc == rem, removes from queue without mutating version
        try await engine.synchronize()
        #expect(await queue.count() == 0)

        let local1 = try await localStore.fetch(id: "idempotent-rec-1")
        let cloud1 = try await cloudStore.pull(id: "idempotent-rec-1")
        #expect(local1?.version == 2)
        #expect(cloud1?.version == 2)

        // Enqueue again and run second sync pass
        try await engine.enqueueLocalChange(id: "idempotent-rec-1")
        try await engine.synchronize()

        let local2 = try await localStore.fetch(id: "idempotent-rec-1")
        let cloud2 = try await cloudStore.pull(id: "idempotent-rec-1")

        // Invariant: version strictly stays 2 (no artificial version increment)
        #expect(local2?.version == 2)
        #expect(cloud2?.version == 2)
        #expect(local2?.revisionToken == "token-v2")
    }
}
