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

    // 3. valid direct parent token -> PASS
    @Test func testValidDirectParentTokenIsDescendant() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let remoteRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "direct-parent-1"),
                kind: .fact,
                content: "Remote version 1",
                provenance: Provenance(source: "agent"),
                version: 1,
                revisionToken: "token-v1"
            )
        )

        let localRecord = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "direct-parent-1"),
                kind: .fact,
                content: "Local version 2 (parent was 1)",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-v2",
                parentRevisionToken: "token-v1",
                ancestorRevisionTokens: ["token-v1"]
            )
        )

        try await localStore.upsert(localRecord)
        await cloudStore.setRecordDirectly(remoteRecord)

        #expect(localRecord.isDescendant(of: remoteRecord))

        try await engine.enqueueLocalChange(id: "direct-parent-1")
        try await engine.synchronize()

        // Local record is proven descendant of remote -> local pushed to cloud successfully
        let cloudFetched = try await cloudStore.pull(id: "direct-parent-1")
        #expect(cloudFetched?.version == 2)
        #expect(cloudFetched?.record.content == "Local version 2 (parent was 1)")
        #expect(await queue.count() == 0)
    }

    // 4. valid multi-generation lineage -> PASS
    @Test func testValidMultiGenerationAncestryV1ToV2ToV3() async throws {
        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "multi-gen-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-1"
            )
        )

        let v2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "multi-gen-1"),
                kind: .fact,
                content: "V2 content",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-2",
                parentRevisionToken: "token-1",
                ancestorRevisionTokens: ["token-1"]
            )
        )

        let v3 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "multi-gen-1"),
                kind: .fact,
                content: "V3 content",
                provenance: Provenance(source: "user"),
                version: 3,
                parentVersion: 2,
                revisionToken: "token-3",
                parentRevisionToken: "token-2",
                ancestorRevisionTokens: ["token-1", "token-2"]
            )
        )

        #expect(v2.isDescendant(of: v1) == true)
        #expect(v3.isDescendant(of: v2) == true)
        #expect(v3.isDescendant(of: v1) == true, "v3 MUST be proven descendant of v1 across multi-generation lineage")
    }

    // 5. missing parent proof -> FAIL
    @Test func testMissingParentProofIsNotDescendant() async throws {
        let localV1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "missing-proof-1"),
                kind: .fact,
                content: "Local v1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-v1"
            )
        )

        let remoteV2NoParentToken = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "missing-proof-1"),
                kind: .fact,
                content: "Remote v2 content with nil parentRevisionToken",
                provenance: Provenance(source: "agent"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-v2",
                parentRevisionToken: nil
            )
        )

        #expect(!remoteV2NoParentToken.isDescendant(of: localV1))
    }

    // 6. forged ancestor token only -> FAIL
    @Test func testForgedAncestorTokenOnlyIsNotDescendant() async throws {
        let localV1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "forged-token-only-1"),
                kind: .fact,
                content: "Local v1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "unique-local-v1-token"
            )
        )

        let remoteV5Forged = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "forged-token-only-1"),
                kind: .fact,
                content: "Forged remote v5 content",
                provenance: Provenance(source: "agent"),
                version: 5,
                parentVersion: 4,
                revisionToken: "remote-v5-token",
                parentRevisionToken: "unrelated-parent-token",
                ancestorRevisionTokens: ["unique-local-v1-token", "remote-v1-token", "remote-v2-token"]
            )
        )

        #expect(!remoteV5Forged.isDescendant(of: localV1))
    }

    // 7. forged parent token + forged ancestor token -> FAIL
    @Test func testForgedParentTokenAndForgedAncestorTokenIsNotDescendant() async throws {
        let localV1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "forged-both-1"),
                kind: .fact,
                content: "Local v1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "unique-local-v1-token"
            )
        )

        let remoteV5ForgedBoth = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "forged-both-1"),
                kind: .fact,
                content: "Forged remote v5 claiming local v1 token as parentRevisionToken",
                provenance: Provenance(source: "agent"),
                version: 5,
                parentVersion: 4,
                revisionToken: "remote-v5-token",
                parentRevisionToken: "unique-local-v1-token",
                ancestorRevisionTokens: ["unique-local-v1-token"]
            )
        )

        // Must return false because parentVersion (4) != self.version - 1 (4 != 4 for direct parent),
        // and multi-gen verification requires self.ancestorRevisionTokens to contain parentRevisionToken ("unique-local-v1-token")
        // and ancestor.revisionToken. BUT for v5 claiming parentVersion 4, parentVersion != self.version - 1 fails sequential check!
        #expect(!remoteV5ForgedBoth.isDescendant(of: localV1))
    }

    // 8. broken intermediate lineage -> FAIL
    @Test func testBrokenIntermediateLineageIsNotDescendant() async throws {
        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "broken-lineage-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-1"
            )
        )

        let v3Broken = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "broken-lineage-1"),
                kind: .fact,
                content: "V3 content without v2 parent linkage",
                provenance: Provenance(source: "user"),
                version: 3,
                parentVersion: 1, // Non-sequential step (version 3 with parentVersion 1)
                revisionToken: "token-3",
                parentRevisionToken: "token-1",
                ancestorRevisionTokens: ["token-1"]
            )
        )

        #expect(!v3Broken.isDescendant(of: v1))
    }

    // 9. cyclic lineage -> FAIL
    @Test func testCyclicLineageIsNotDescendant() async throws {
        let v1 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "cyclic-lineage-1"),
                kind: .fact,
                content: "V1 content",
                provenance: Provenance(source: "user"),
                version: 1,
                revisionToken: "token-1"
            )
        )

        let v2Cyclic = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "cyclic-lineage-1"),
                kind: .fact,
                content: "V2 content pointing to itself as parent",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "token-2",
                parentRevisionToken: "token-2",
                ancestorRevisionTokens: ["token-1", "token-2"]
            )
        )

        #expect(!v2Cyclic.isDescendant(of: v1))
    }

    // 10. divergent lineage -> FAIL
    @Test func testDivergentLineageIsNotDescendant() async throws {
        let localV2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "divergent-1"),
                kind: .fact,
                content: "Local v2 from parent 1",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "local-v2-token",
                parentRevisionToken: "parent-v1-token"
            )
        )

        let remoteV2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "divergent-1"),
                kind: .fact,
                content: "Remote v2 from parent 1 (divergent content)",
                provenance: Provenance(source: "agent"),
                version: 2,
                parentVersion: 1,
                revisionToken: "remote-v2-token",
                parentRevisionToken: "parent-v1-token"
            )
        )

        #expect(!remoteV2.isDescendant(of: localV2))
        #expect(!localV2.isDescendant(of: remoteV2))
    }

    // 11. same version / different lineage -> conflict
    @Test func testSameVersionDifferentLineageIsConflict() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let localV2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "same-ver-conflict-1"),
                kind: .fact,
                content: "Local v2",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "local-v2-token",
                parentRevisionToken: "v1-token"
            )
        )

        let remoteV2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "same-ver-conflict-1"),
                kind: .fact,
                content: "Remote v2",
                provenance: Provenance(source: "agent"),
                version: 2,
                parentVersion: 1,
                revisionToken: "remote-v2-token",
                parentRevisionToken: "v1-token"
            )
        )

        try await localStore.upsert(localV2)
        await cloudStore.setRecordDirectly(remoteV2)

        try await engine.enqueueLocalChange(id: "same-ver-conflict-1")
        try await engine.synchronize()

        let conflicts = await engine.pendingConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.local.id == "same-ver-conflict-1")
    }

    // 12. higher version / unknown lineage -> conflict
    @Test func testHigherVersionUnknownLineageIsConflict() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let localV2 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "higher-ver-unknown-1"),
                kind: .fact,
                content: "Local v2",
                provenance: Provenance(source: "user"),
                version: 2,
                parentVersion: 1,
                revisionToken: "local-v2-token",
                parentRevisionToken: "local-v1-token"
            )
        )

        let remoteV4Unknown = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "higher-ver-unknown-1"),
                kind: .fact,
                content: "Remote v4 with unknown parent lineage",
                provenance: Provenance(source: "agent"),
                version: 4,
                parentVersion: 3,
                revisionToken: "remote-v4-token",
                parentRevisionToken: "remote-v3-token",
                ancestorRevisionTokens: ["remote-v1-token", "remote-v2-token", "remote-v3-token"]
            )
        )

        try await localStore.upsert(localV2)
        await cloudStore.setRecordDirectly(remoteV4Unknown)

        #expect(!remoteV4Unknown.isDescendant(of: localV2))
        #expect(!localV2.isDescendant(of: remoteV4Unknown))

        try await engine.enqueueLocalChange(id: "higher-ver-unknown-1")
        try await engine.synchronize()

        let conflicts = await engine.pendingConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.local.id == "higher-ver-unknown-1")

        let localFetched = try await localStore.fetch(id: "higher-ver-unknown-1")
        #expect(localFetched?.version == 2)
        #expect(localFetched?.record.content == "Local v2")
    }

    // 13. version-gap resolution produces valid chain v4 -> v5 -> v6 -> v7 with immediate parent pointers
    @Test func testVersionGapConflictResolutionProducesValidChainV4ToV7() async throws {
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

        let localV4 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "version-gap-rec-1"),
                kind: .fact,
                content: "Local v4 content",
                provenance: Provenance(source: "user"),
                version: 4,
                parentVersion: 3
            )
        )

        let remoteV6 = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "version-gap-rec-1"),
                kind: .fact,
                content: "Remote v6 content",
                provenance: Provenance(source: "agent"),
                version: 6,
                parentVersion: 5
            )
        )

        try await localStore.upsert(localV4)
        await cloudStore.setRecordDirectly(remoteV6)

        // Conflict: local v4 and remote v6 have no direct parent/child link
        #expect(!remoteV6.isDescendant(of: localV4))
        #expect(!localV4.isDescendant(of: remoteV6))

        let conflict = SyncConflict(local: localV4, remote: remoteV6)
        try await engine.resolve(conflict, policy: .keepLocal)

        // Fetch final local revision
        let localFinal = try await localStore.fetch(id: "version-gap-rec-1")
        let cloudFinal = try await cloudStore.pull(id: "version-gap-rec-1")

        // Assertions:
        // * stable ID unchanged
        // * final version == 7
        // * v7.parentVersion == 6
        // * cloud receives final authoritative v7
        #expect(localFinal?.id == "version-gap-rec-1")
        #expect(localFinal?.version == 7)
        #expect(localFinal?.parentVersion == 6, "v7 MUST have immediate parent version 6")
        #expect(cloudFinal?.version == 7)
        #expect(cloudFinal?.parentVersion == 6)
        #expect(cloudFinal?.record.content == "Local v4 content")
    }

    // 14. persisted/reloaded lineage verifies correctly
    @Test func testPersistedAndReloadedLineageVerifiesCorrectly() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5LineagePersist_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let v1Record = MemoryRecord(
            id: MemoryRecordID(rawValue: "persist-lineage-1"),
            kind: .fact,
            content: "V1 content",
            provenance: Provenance(source: "user"),
            version: 1,
            revisionToken: "persist-v1-token"
        )

        // Step 1: Write v1 to FileBackedMemoryStore
        let store1 = try FileBackedMemoryStore(directoryURL: tempDir)
        try await store1.upsert(MemoryStorageRecord(v1Record))

        // Step 2: Update to v2 via store1
        let v1Fetched = try await store1.fetch(id: "persist-lineage-1")
        #expect(v1Fetched != nil)

        let v2Record = v1Record.updating(content: "V2 content")
        try await store1.upsert(MemoryStorageRecord(v2Record))

        // Step 3: Re-open store2 from same directory and verify lineage
        let store2 = try FileBackedMemoryStore(directoryURL: tempDir)
        let v2Fetched = try await store2.fetch(id: "persist-lineage-1")

        #expect(v2Fetched != nil)
        #expect(v2Fetched?.version == 2)
        #expect(v2Fetched?.parentVersion == 1)
        #expect(v2Fetched?.parentRevisionToken == "persist-v1-token")
        #expect(v2Fetched?.isDescendant(of: MemoryStorageRecord(v1Record)) == true)
    }

    // 15. each conflict policy behaves explicitly
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

            try await localStore.upsert(localRecord)

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

    // 16. repeated/resumed sync is idempotent
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

    // 17. cloud failure preserves local state and queued work
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

    // 18. M0-M5.2 regression & contract boundaries
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
