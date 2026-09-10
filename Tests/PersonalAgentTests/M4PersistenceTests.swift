import Testing
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import PAFoundation
import PAStorage
import PAMemory

@Suite("M4 Persistence Tests")
struct M4PersistenceTests {
    @Test func fileBackedStorePersistsDataAcrossRuntimeRecreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Persist_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rec1 = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-persist-1"),
            kind: .fact,
            content: "User lives in Tokyo",
            provenance: Provenance(source: "user"),
            scope: .agent,
            importance: 0.9
        )

        let rec2 = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-persist-2"),
            kind: .preference,
            content: "User prefers Japanese tea",
            provenance: Provenance(source: "user"),
            scope: .agent,
            importance: 0.7
        )

        // Phase 1: Write records in store instance 1
        do {
            let store1 = try FileBackedMemoryStore(directoryURL: tempDir)
            try await store1.capture(rec1)
            try await store1.capture(rec2)
        }

        // Phase 2: Create store instance 2 pointing to the same directory
        let store2 = try FileBackedMemoryStore(directoryURL: tempDir)
        let fetched1 = try await store2.retrieve(id: rec1.id)
        let fetched2 = try await store2.retrieve(id: rec2.id)

        #expect(fetched1 != nil)
        #expect(fetched1?.content == "User lives in Tokyo")
        #expect(fetched1?.importance == 0.9)

        #expect(fetched2 != nil)
        #expect(fetched2?.content == "User prefers Japanese tea")
        #expect(fetched2?.importance == 0.7)
    }

    @Test func storeReloadRebuildsInMemoryIndexesFromDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Reload_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)

        let rec = MemoryRecord(
            kind: .event,
            content: "Keynote presentation",
            provenance: Provenance(source: "calendar")
        )

        try await store.capture(rec)

        // Trigger store reload
        try await store.reload()

        let fetched = try await store.retrieve(id: rec.id)
        #expect(fetched != nil)
        #expect(fetched?.content == "Keynote presentation")
    }

    @Test func corruptSnapshotFileThrowsCorruptRecordErrorAndFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Corrupt_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)
        let rec = MemoryRecord(kind: .observation, content: "Test", provenance: Provenance(source: "sensor"))
        try await store.capture(rec)

        // Intentionally corrupt store.json on disk
        let storeFile = tempDir.appendingPathComponent("store.json")
        try "CORRUPT INVALID JSON {{{".write(to: storeFile, atomically: true, encoding: .utf8)

        #expect(throws: MemoryError.self) {
            _ = try FileBackedMemoryStore(directoryURL: tempDir)
        }
    }

    @Test func unsupportedSchemaVersionFailsClosedWithUnsupportedVersionError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Version_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)
        let rec = MemoryRecord(kind: .fact, content: "Version test", provenance: Provenance(source: "test"))
        try await store.capture(rec)

        // Write store.json with unsupported schema version (e.g. version 99)
        let storeFile = tempDir.appendingPathComponent("store.json")
        let invalidMetaJSON = """
        {
          "metadata": {
            "version": 99,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "recordCount": 1
          },
          "records": []
        }
        """
        try invalidMetaJSON.write(to: storeFile, atomically: true, encoding: .utf8)

        #expect(throws: MemoryError.self) {
            _ = try FileBackedMemoryStore(directoryURL: tempDir)
        }
    }

    @Test func staleVersionUpdateThrowsConcurrentConflict() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Conflict_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)
        let original = MemoryRecord(kind: .fact, content: "Initial content", provenance: Provenance(source: "user"))
        try await store.capture(original)

        // Produce two copies with version = 1
        let copyA = original
        let copyB = original

        // Update A -> version becomes 2 in store
        let updateA = copyA.updating(content: "Content from A")
        try await store.update(updateA)

        // Attempting to update stale copy B (which still has version = 1) must throw concurrentConflict
        let updateB = copyB.updating(content: "Content from B")
        await #expect(throws: MemoryError.self) {
            try await store.update(updateB)
        }
    }

    @Test func schemaVersionsZeroNegativeAndFutureThrowUnsupportedVersion() async throws {
        let invalidVersions = [0, -1, -99, 2, 100]

        for v in invalidVersions {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("M4VerTest_\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let storeFile = tempDir.appendingPathComponent("store.json")
            let metaJSON = """
            {
              "metadata": {
                "version": \(v),
                "createdAt": "2026-01-01T00:00:00Z",
                "updatedAt": "2026-01-01T00:00:00Z",
                "recordCount": 0
              },
              "records": []
            }
            """
            try metaJSON.write(to: storeFile, atomically: true, encoding: .utf8)

            #expect(throws: MemoryError.unsupportedVersion(v)) {
                _ = try FileBackedMemoryStore(directoryURL: tempDir)
            }
        }
    }

    @Test func directoryCreationFailureThrowsPersistenceFailed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4DirFile_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a regular file where directory is expected
        let fakeFilePath = tempDir.appendingPathComponent("file_not_dir")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "I am a file".write(to: fakeFilePath, atomically: true, encoding: .utf8)

        let targetDirURL = fakeFilePath.appendingPathComponent("sub_dir")

        #expect(throws: MemoryError.self) {
            _ = try FileBackedMemoryStore(directoryURL: targetDirURL)
        }
    }

    @Test func persistenceFailureRollsBackInMemoryAndOnDiskState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Rollback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            #if canImport(Glibc)
            seteuid(0)
            #elseif canImport(Darwin)
            seteuid(0)
            #endif
            chmod(tempDir.path, 0o755)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)

        let rec1 = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-committed-1"),
            kind: .fact,
            content: "Committed Fact 1",
            provenance: Provenance(source: "user")
        )
        try await store.capture(rec1)

        let storeFileURL = tempDir.appendingPathComponent("store.json")
        let previousCommittedBytes = try Data(contentsOf: storeFileURL)

        // Make write fail deterministically by making directory read-only (chmod 0555) and dropping euid
        chmod(tempDir.path, 0o555)
        #if canImport(Glibc)
        seteuid(1000)
        #elseif canImport(Darwin)
        seteuid(1000)
        #endif

        let rec2 = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-fail-2"),
            kind: .fact,
            content: "Uncommitted Fact 2",
            provenance: Provenance(source: "user")
        )

        // Attempting to capture rec2 must fail and throw MemoryError.persistenceFailed specifically
        do {
            try await store.capture(rec2)
            Issue.record("Expected capture to throw MemoryError.persistenceFailed")
        } catch let err as MemoryError {
            if case .persistenceFailed = err {
                // Expected error case
            } else {
                Issue.record("Expected MemoryError.persistenceFailed, got \(err)")
            }
        } catch {
            Issue.record("Expected MemoryError, got \(error)")
        }

        // Restore euid and write permissions so we can inspect disk and clean up
        #if canImport(Glibc)
        seteuid(0)
        #elseif canImport(Darwin)
        seteuid(0)
        #endif
        chmod(tempDir.path, 0o755)

        // Prove BOTH:
        // 1. In-memory state == previous committed state (count == 1, rec2 not present)
        let countAfter = try await store.count()
        #expect(countAfter == 1)

        let inMemoryRec2 = try await store.retrieve(id: rec2.id)
        #expect(inMemoryRec2 == nil)

        let inMemoryRec1 = try await store.retrieve(id: rec1.id)
        #expect(inMemoryRec1?.content == "Committed Fact 1")

        // 2. On-disk store.json bytes == previousCommittedBytes
        let currentDiskBytes = try Data(contentsOf: storeFileURL)
        #expect(currentDiskBytes == previousCommittedBytes)
    }

    @Test func bulkInsertRejectsDuplicateIDsInBatchAndStoreAtomically() async throws {
        let store = InMemoryMemoryStore()

        let existing = MemoryRecord(
            id: MemoryRecordID(rawValue: "existing-1"),
            kind: .fact,
            content: "Existing record",
            provenance: Provenance(source: "user")
        )
        try await store.capture(existing)

        let r1 = MemoryRecord(id: MemoryRecordID(rawValue: "batch-1"), kind: .fact, content: "Batch 1", provenance: Provenance(source: "user"))
        let r2 = MemoryRecord(id: MemoryRecordID(rawValue: "batch-2"), kind: .fact, content: "Batch 2", provenance: Provenance(source: "user"))
        let rDuplicateExisting = MemoryRecord(id: MemoryRecordID(rawValue: "existing-1"), kind: .fact, content: "Duplicate Existing", provenance: Provenance(source: "user"))

        // Rejection due to duplicate with existing record in store
        await #expect(throws: MemoryError.duplicateID(existing.id)) {
            try await store.bulkInsert([r1, r2, rDuplicateExisting])
        }

        // Prove entire batch remains uncommitted
        #expect(try await store.count() == 1)
        #expect(try await store.retrieve(id: r1.id) == nil)

        let rDup1 = MemoryRecord(id: MemoryRecordID(rawValue: "dup-batch"), kind: .fact, content: "Dup 1", provenance: Provenance(source: "user"))
        let rDup2 = MemoryRecord(id: MemoryRecordID(rawValue: "dup-batch"), kind: .fact, content: "Dup 2", provenance: Provenance(source: "user"))

        // Rejection due to intra-batch duplicate IDs
        await #expect(throws: MemoryError.duplicateID(rDup1.id)) {
            try await store.bulkInsert([rDup1, rDup2])
        }

        // Prove entire batch remains uncommitted
        #expect(try await store.count() == 1)
        #expect(try await store.retrieve(id: rDup1.id) == nil)
    }

    @Test func directStoreRejectsInvalidRecords() async throws {
        let store = InMemoryMemoryStore()

        let emptyContent = MemoryRecord(kind: .fact, content: "   ", provenance: Provenance(source: "user"))
        await #expect(throws: MemoryError.invalidRecord("Record content cannot be empty")) {
            try await store.capture(emptyContent)
        }

        let nanImportance = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: Double.nan)
        await #expect(throws: MemoryError.invalidRecord("Record importance must be finite and within [0.0, 1.0]")) {
            try await store.capture(nanImportance)
        }

        let infImportance = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: Double.infinity)
        await #expect(throws: MemoryError.invalidRecord("Record importance must be finite and within [0.0, 1.0]")) {
            try await store.capture(infImportance)
        }

        let negativeImportance = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: -0.1)
        await #expect(throws: MemoryError.invalidRecord("Record importance must be finite and within [0.0, 1.0]")) {
            try await store.capture(negativeImportance)
        }

        let overflowImportance = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: 1.01)
        await #expect(throws: MemoryError.invalidRecord("Record importance must be finite and within [0.0, 1.0]")) {
            try await store.capture(overflowImportance)
        }
    }
}
