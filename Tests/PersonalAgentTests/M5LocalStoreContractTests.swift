import Testing
import Foundation
import PAFoundation
import PAStorage
import PAMemory
import PAArchitecture

private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { self._value = value }
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@Suite("M5.1 LocalStore Contract Tests")
struct M5LocalStoreContractTests {
    private func exerciseUpsertAndFetch<S: LocalStore>(store: S) async throws where S.Record == MemoryStorageRecord {
        let memRecord = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-rec-1"),
            kind: .fact,
            content: "LocalStore contract test fact",
            provenance: Provenance(source: "user"),
            version: 1
        )
        let storageRecord = MemoryStorageRecord(memRecord)

        // Exercise upsert through LocalStore protocol contract
        try await store.upsert(storageRecord)

        // Exercise fetch through LocalStore protocol contract
        let fetched = try await store.fetch(id: "m5-rec-1")

        #expect(fetched != nil)
        #expect(fetched?.id == "m5-rec-1")
        #expect(fetched?.version == 1)
        #expect(fetched?.record.content == "LocalStore contract test fact")
    }

    private func exerciseUpdateAndVersionIncrement<S: LocalStore>(store: S) async throws where S.Record == MemoryStorageRecord {
        let initialMem = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-rec-2"),
            kind: .preference,
            content: "Initial preference",
            provenance: Provenance(source: "user"),
            version: 1
        )
        try await store.upsert(MemoryStorageRecord(initialMem))

        // Update record content using matching version 1
        let updatedMem = initialMem.updating(content: "Updated preference")
        try await store.upsert(MemoryStorageRecord(updatedMem))

        let fetched = try await store.fetch(id: "m5-rec-2")

        #expect(fetched != nil)
        #expect(fetched?.id == "m5-rec-2")
        #expect(fetched?.version == 2)
        #expect(fetched?.record.content == "Updated preference")
    }

    private func exerciseForget<S: LocalStore>(store: S) async throws where S.Record == MemoryStorageRecord {
        let memRecord = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-rec-3"),
            kind: .episodic,
            content: "Episodic memory to delete",
            provenance: Provenance(source: "system"),
            version: 1
        )
        try await store.upsert(MemoryStorageRecord(memRecord))

        // Exercise forget via LocalStore interface
        try await store.forget(id: "m5-rec-3")

        let fetched = try await store.fetch(id: "m5-rec-3")

        #expect(fetched != nil)
        #expect(fetched?.id == "m5-rec-3")
        #expect(fetched?.record.lifecycle == .deleted)
        #expect(fetched?.version == 2)
    }

    @Test func testLocalStoreUpsertAndFetchPreservesIdentityAndVersion() async throws {
        let store = InMemoryMemoryStore()
        try await exerciseUpsertAndFetch(store: store)
    }

    @Test func testLocalStoreUpsertUpdatesExistingRecordAndIncrementsVersion() async throws {
        let store = InMemoryMemoryStore()
        try await exerciseUpdateAndVersionIncrement(store: store)
    }

    @Test func testLocalStoreRejectsStaleVersionUpsert() async throws {
        let store = InMemoryMemoryStore()

        let initialMem = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-stale-1"),
            kind: .fact,
            content: "Initial content",
            provenance: Provenance(source: "user"),
            version: 1
        )
        try await store.upsert(MemoryStorageRecord(initialMem))

        // Update once -> version in store becomes 2
        let update1 = initialMem.updating(content: "First valid update")
        try await store.upsert(MemoryStorageRecord(update1))

        // Attempting to upsert with initialMem (which still has version = 1) must be rejected with concurrentConflict
        let staleUpdate = initialMem.updating(content: "Stale update attempting overwrite")
        do {
            try await store.upsert(MemoryStorageRecord(staleUpdate))
            Issue.record("Expected stale upsert to throw concurrentConflict error")
        } catch let err as MemoryError {
            if case .concurrentConflict = err {
                // Expected
            } else {
                Issue.record("Expected concurrentConflict, got \(err)")
            }
        } catch {
            Issue.record("Expected MemoryError, got \(error)")
        }

        // Verify stored state remains at version 2 with First valid update
        let fetched = try await store.fetch(id: "m5-stale-1")
        #expect(fetched?.version == 2)
        #expect(fetched?.record.content == "First valid update")
    }

    @Test func testLocalStoreDeleteMarksRecordDeletedAndIncrementsVersion() async throws {
        let store = InMemoryMemoryStore()
        try await exerciseForget(store: store)
    }

    @Test func testLocalStorePersistenceAndReload() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5LocalStorePersist_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rec = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-persist-1"),
            kind: .semantic,
            content: "Durable local persistence test",
            provenance: Provenance(source: "user"),
            version: 1
        )

        // Step 1: Write via FileBackedMemoryStore through LocalStore interface
        do {
            let store1 = try FileBackedMemoryStore(directoryURL: tempDir)
            try await writeToStore(store1, record: MemoryStorageRecord(rec))
        }

        // Step 2: Re-open store from same directory and fetch via LocalStore interface
        let store2 = try FileBackedMemoryStore(directoryURL: tempDir)
        let fetched = try await fetchFromStore(store2, id: "m5-persist-1")

        #expect(fetched != nil)
        #expect(fetched?.id == "m5-persist-1")
        #expect(fetched?.record.content == "Durable local persistence test")
        #expect(fetched?.version == 1)
    }

    @Test func testLocalStoreFailedPersistenceRollsBackInMemState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5LocalStoreRollback_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shouldFail = AtomicBool(false)

        let store = try FileBackedMemoryStore(
            directoryURL: tempDir,
            fileWriter: { data, url in
                if shouldFail.value {
                    throw MemoryError.persistenceFailed("Simulated write failure")
                }
                try data.write(to: url, options: .atomic)
            }
        )

        let rec1 = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-committed-1"),
            kind: .fact,
            content: "Committed Fact 1",
            provenance: Provenance(source: "user")
        )
        try await writeToStore(store, record: MemoryStorageRecord(rec1))

        // Inject persistence failure
        shouldFail.value = true

        let rec2 = MemoryRecord(
            id: MemoryRecordID(rawValue: "m5-fail-2"),
            kind: .fact,
            content: "Uncommitted Fact 2",
            provenance: Provenance(source: "user")
        )

        do {
            try await writeToStore(store, record: MemoryStorageRecord(rec2))
            Issue.record("Expected upsert to fail when persistence fails")
        } catch let err as MemoryError {
            if case .persistenceFailed = err {
                // Expected
            } else {
                Issue.record("Expected persistenceFailed, got \(err)")
            }
        } catch {
            Issue.record("Expected MemoryError, got \(error)")
        }

        // Verify rec2 was rolled back and rec1 remains intact
        let fetch2 = try await fetchFromStore(store, id: "m5-fail-2")
        #expect(fetch2 == nil)

        let fetch1 = try await fetchFromStore(store, id: "m5-committed-1")
        #expect(fetch1 != nil)
        #expect(fetch1?.record.content == "Committed Fact 1")
    }

    @Test func testStorageModuleHasNoDependencyOnPAMemory() throws {
        guard let allowedStorageImports = ArchitectureManifest.allowedImports["PAStorage"] else {
            Issue.record("PAStorage mapping missing from ArchitectureManifest")
            return
        }

        #expect(!allowedStorageImports.contains("PAMemory"), "PAStorage MUST NOT import PAMemory")
    }

    private func writeToStore<S: LocalStore>(_ store: S, record: S.Record) async throws {
        try await store.upsert(record)
    }

    private func fetchFromStore<S: LocalStore>(_ store: S, id: String) async throws -> S.Record? {
        try await store.fetch(id: id)
    }
}
