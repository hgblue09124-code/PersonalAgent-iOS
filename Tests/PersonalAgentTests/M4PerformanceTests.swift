import Testing
import Foundation
import PAFoundation
import PAMemory

@Suite("M4 Performance & Scale Benchmarks")
struct M4PerformanceTests {
    @Test func benchmarkIndexQueryScalingUpTo100kEntries() async throws {
        let store = InMemoryMemoryStore()

        let scales = [100, 1000, 10_000, 50_000]

        for scale in scales {
            let startCount = try await store.count(scope: nil)
            let needed = scale - startCount

            if needed > 0 {
                var records: [MemoryRecord] = []
                records.reserveCapacity(needed)

                for i in startCount..<scale {
                    let id = MemoryRecordID(rawValue: "perf-rec-\(i)")
                    let kind: MemoryKind = (i % 2 == 0) ? .fact : .preference
                    let scope: MemoryScope = (i % 3 == 0) ? .session : .agent
                    let envVal = (i % 2 == 0) ? "prod" : "test"
                    let meta: MemoryMetadata = ["env": envVal]
                    let importanceVal = Double(i % 100) / 100.0

                    let rec = MemoryRecord(
                        id: id,
                        kind: kind,
                        content: "Personal agent observation item \(i) with keyword alpha\(i % 10)",
                        provenance: Provenance(source: "perf-harness"),
                        scope: scope,
                        importance: importanceVal,
                        metadata: meta
                    )
                    records.append(rec)
                }

                try await store.bulkInsert(records)
            }

            // Benchmark 1: O(1) ID Lookup
            let targetID = MemoryRecordID(rawValue: "perf-rec-\(scale / 2)")
            let startLookup = DispatchTime.now().uptimeNanoseconds
            let fetched = try await store.retrieve(id: targetID)
            let endLookup = DispatchTime.now().uptimeNanoseconds
            let lookupDurationMs = Double(endLookup - startLookup) / 1_000_000.0

            #expect(fetched != nil)
            #expect(lookupDurationMs < 50.0, "Scale \(scale): ID lookup exceeded 50ms (was \(lookupDurationMs)ms)")

            // Benchmark 2: Scope + Kind Filtered Query
            let query = MemoryQuery(
                scopes: [.session],
                kinds: [.fact],
                limit: 50,
                sortOrder: .importanceDescending
            )
            let res = try await store.query(query)
            let queryDurationMs = Double(res.executionDurationNanoseconds) / 1_000_000.0

            #expect(res.records.count <= 50)
            #expect(queryDurationMs < 200.0, "Scale \(scale): Filtered query exceeded 200ms (was \(queryDurationMs)ms)")

            // Benchmark 3: Full-Text Lexical Search Query
            let textQuery = MemoryQuery(textSearch: "alpha5", limit: 20)
            let textRes = try await store.query(textQuery)
            let textDurationMs = Double(textRes.executionDurationNanoseconds) / 1_000_000.0

            #expect(textRes.records.count > 0)
            #expect(textDurationMs < 300.0, "Scale \(scale): Text search query exceeded 300ms (was \(textDurationMs)ms)")
        }
    }

    @Test func benchmarkFileBackedStoreReloadPerformanceAtScale() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4PerfReload_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)

        let recordCount = 5000
        var records: [MemoryRecord] = []
        records.reserveCapacity(recordCount)

        for i in 0..<recordCount {
            let rec = MemoryRecord(
                id: MemoryRecordID(rawValue: "file-perf-\(i)"),
                kind: .observation,
                content: "File backed record item \(i) for scale reload testing",
                provenance: Provenance(source: "disk-test"),
                scope: .global
            )
            records.append(rec)
        }

        let startWrite = DispatchTime.now().uptimeNanoseconds
        try await store.bulkInsert(records)
        let endWrite = DispatchTime.now().uptimeNanoseconds
        let writeDurationMs = Double(endWrite - startWrite) / 1_000_000.0

        #expect(writeDurationMs < 3000.0, "Bulk insert 5,000 records exceeded 3s (was \(writeDurationMs)ms)")

        // Benchmark store reload (reads from disk and rebuilds in-memory index)
        let startReload = DispatchTime.now().uptimeNanoseconds
        try await store.reload()
        let endReload = DispatchTime.now().uptimeNanoseconds
        let reloadDurationMs = Double(endReload - startReload) / 1_000_000.0

        #expect(reloadDurationMs < 1000.0, "Reload 5,000 records exceeded 1s (was \(reloadDurationMs)ms)")

        let count = try await store.count(scope: .global)
        #expect(count == recordCount)
    }
}
