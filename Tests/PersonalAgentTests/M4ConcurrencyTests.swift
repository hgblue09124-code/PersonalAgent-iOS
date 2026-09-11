import Testing
import Foundation
import PAFoundation
import PAEvents
import PAMemory

@Suite("M4 Concurrency Tests")
struct M4ConcurrencyTests {
    @Test func concurrentWritesDoNotCorruptStoreOrLoseUpdates() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let taskCount = 50
        let itemsPerTask = 20

        try await withThrowingTaskGroup(of: Void.self) { group in
            for t in 0..<taskCount {
                group.addTask {
                    for i in 0..<itemsPerTask {
                        let rec = MemoryRecord(
                            id: MemoryRecordID(rawValue: "conc-write-\(t)-\(i)"),
                            kind: .fact,
                            content: "Concurrent fact \(t)-\(i)",
                            provenance: Provenance(source: "task-\(t)"),
                            scope: .agent
                        )
                        try await runtime.capture(rec)
                    }
                }
            }
            try await group.waitForAll()
        }

        let totalCount = try await runtime.count()
        #expect(totalCount == taskCount * itemsPerTask)
    }

    @Test func concurrentReadsAndWritesAreSafeAndIsolated() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        // Seed store with initial records
        for i in 0..<100 {
            let rec = MemoryRecord(
                id: MemoryRecordID(rawValue: "seed-\(i)"),
                kind: .observation,
                content: "Seed observation \(i)",
                provenance: Provenance(source: "seed"),
                scope: .agent
            )
            try await runtime.capture(rec)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Writer tasks
            for t in 0..<10 {
                group.addTask {
                    for i in 0..<10 {
                        let rec = MemoryRecord(
                            id: MemoryRecordID(rawValue: "writer-\(t)-\(i)"),
                            kind: .preference,
                            content: "Preference \(t)-\(i)",
                            provenance: Provenance(source: "writer")
                        )
                        try await runtime.capture(rec)
                    }
                }
            }

            // Reader tasks
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<10 {
                        let query = MemoryQuery(kinds: [.observation, .preference])
                        let res = try await runtime.query(query)
                        #expect(res.records.count >= 100)
                    }
                }
            }
            try await group.waitForAll()
        }

        let finalCount = try await runtime.count()
        #expect(finalCount == 200)
    }

    @Test func sendableTypesCrossActorBoundariesWithoutRaces() async throws {
        let query = MemoryQuery(
            scopes: [.agent, .global],
            kinds: [.fact, .preference],
            textSearch: "sendable search",
            minImportance: 0.5,
            limit: 25,
            sortOrder: .importanceDescending
        )

        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let res = try await Task.detached {
            try await runtime.query(query)
        }.value

        #expect(res.records.isEmpty)
        #expect(res.totalCount == 0)
    }
}
