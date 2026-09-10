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

    @Test func corruptRecordsFileThrowsCorruptRecordErrorAndFailsClosed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Corrupt_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)
        let rec = MemoryRecord(kind: .observation, content: "Test", provenance: Provenance(source: "sensor"))
        try await store.capture(rec)

        // Intentionally corrupt records.json on disk
        let recordsFile = tempDir.appendingPathComponent("records.json")
        try "CORRUPT INVALID JSON {{{".write(to: recordsFile, atomically: true, encoding: .utf8)

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

        // Write metadata with unsupported schema version (e.g. version 99)
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        let invalidMetaJSON = """
        {
          "version": 99,
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "recordCount": 1
        }
        """
        try invalidMetaJSON.write(to: metadataFile, atomically: true, encoding: .utf8)

        #expect(throws: MemoryError.self) {
            _ = try FileBackedMemoryStore(directoryURL: tempDir)
        }
    }

    @Test func updatePersistsToDiskAtomically() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4Update_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rec = MemoryRecord(kind: .instruction, content: "Original instruction", provenance: Provenance(source: "user"))

        do {
            let store1 = try FileBackedMemoryStore(directoryURL: tempDir)
            try await store1.capture(rec)
            let updatedRec = rec.updating(content: "Modified instruction")
            try await store1.update(updatedRec)
        }

        let store2 = try FileBackedMemoryStore(directoryURL: tempDir)
        let fetched = try await store2.retrieve(id: rec.id)
        #expect(fetched?.content == "Modified instruction")
        #expect(fetched?.version == 2)
    }
}
