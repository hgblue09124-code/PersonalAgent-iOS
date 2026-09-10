import Testing
import Foundation
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
}
