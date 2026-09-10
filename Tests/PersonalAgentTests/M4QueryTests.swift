import Testing
import Foundation
import PAFoundation
import PAMemory

@Suite("M4 Query Engine Tests")
struct M4QueryTests {
    @Test func directIDLookupReturnsTargetRecord() async throws {
        let store = InMemoryMemoryStore()

        let rec1 = MemoryRecord(id: MemoryRecordID(rawValue: "id-1"), kind: .fact, content: "Fact 1", provenance: Provenance(source: "user"))
        let rec2 = MemoryRecord(id: MemoryRecordID(rawValue: "id-2"), kind: .fact, content: "Fact 2", provenance: Provenance(source: "user"))

        try await store.capture(rec1)
        try await store.capture(rec2)

        let query = MemoryQuery(ids: [MemoryRecordID(rawValue: "id-2")])
        let result = try await store.query(query)

        #expect(result.records.count == 1)
        #expect(result.records.first?.id.rawValue == "id-2")
    }

    @Test func scopeAndKindFilteringReturnSubset() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(kind: .fact, content: "Agent fact", provenance: Provenance(source: "a"), scope: .agent)
        let r2 = MemoryRecord(kind: .preference, content: "Session pref", provenance: Provenance(source: "a"), scope: .session)
        let r3 = MemoryRecord(kind: .fact, content: "Session fact", provenance: Provenance(source: "a"), scope: .session)

        try await store.bulkInsert([r1, r2, r3])

        let query = MemoryQuery(scopes: [.session], kinds: [.fact])
        let result = try await store.query(query)

        #expect(result.records.count == 1)
        #expect(result.records.first?.content == "Session fact")
    }

    @Test func invertedLexicalSearchMatchesKeywords() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(kind: .observation, content: "Apples and oranges in basket", provenance: Provenance(source: "a"))
        let r2 = MemoryRecord(kind: .observation, content: "Bananas and apples on table", provenance: Provenance(source: "a"))
        let r3 = MemoryRecord(kind: .observation, content: "Cherries in bowl", provenance: Provenance(source: "a"))

        try await store.bulkInsert([r1, r2, r3])

        let query = MemoryQuery(textSearch: "apples")
        let result = try await store.query(query)

        #expect(result.records.count == 2)
        #expect(result.records.allSatisfy { $0.content.contains("apples") || $0.content.contains("Apples") })
    }

    @Test func combinedFieldFilterAndFullTextSearchAndMetadata() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(
            kind: .preference,
            content: "Loves coffee with oat milk",
            provenance: Provenance(source: "a"),
            scope: .agent,
            importance: 0.9,
            metadata: ["location": "home"]
        )

        let r2 = MemoryRecord(
            kind: .preference,
            content: "Loves coffee with almond milk",
            provenance: Provenance(source: "a"),
            scope: .session,
            importance: 0.9,
            metadata: ["location": "home"]
        )

        let r3 = MemoryRecord(
            kind: .fact,
            content: "Coffee shop open at 8am",
            provenance: Provenance(source: "a"),
            scope: .agent,
            importance: 0.4,
            metadata: ["location": "work"]
        )

        try await store.bulkInsert([r1, r2, r3])

        let query = MemoryQuery(
            scopes: [.agent],
            kinds: [.preference],
            textSearch: "coffee",
            minImportance: 0.8,
            metadataFilters: ["location": "home"]
        )

        let result = try await store.query(query)

        #expect(result.records.count == 1)
        #expect(result.records.first?.content == "Loves coffee with oat milk")
    }

    @Test func importanceSortingAndLimitAreDeterministic() async throws {
        let store = InMemoryMemoryStore()

        let records = (1...10).map { i in
            MemoryRecord(
                id: MemoryRecordID(rawValue: "rec-\(i)"),
                kind: .fact,
                content: "Fact item \(i)",
                provenance: Provenance(source: "test"),
                importance: Double(i) / 10.0
            )
        }

        try await store.bulkInsert(records)

        let query = MemoryQuery(limit: 3, sortOrder: .importanceDescending)
        let result = try await store.query(query)

        #expect(result.records.count == 3)
        #expect(result.records[0].importance == 1.0)
        #expect(result.records[1].importance == 0.9)
        #expect(result.records[2].importance == 0.8)
    }

    @Test func relevanceSortOrderRanksByKeywordMatches() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(kind: .fact, content: "Swift language", provenance: Provenance(source: "a"), importance: 0.5)
        let r2 = MemoryRecord(kind: .fact, content: "Swift concurrency in Swift 6", provenance: Provenance(source: "a"), importance: 0.5)

        try await store.bulkInsert([r1, r2])

        let query = MemoryQuery(textSearch: "swift concurrency", sortOrder: .relevance)
        let result = try await store.query(query)

        #expect(result.records.count == 2)
        #expect(result.records.first?.content == "Swift concurrency in Swift 6")
    }
}
