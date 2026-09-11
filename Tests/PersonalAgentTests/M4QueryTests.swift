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

    @Test func invalidQueryNumericBoundariesRejected() async throws {
        let store = InMemoryMemoryStore()

        await #expect(throws: MemoryError.invalidQuery("Limit must be greater than zero")) {
            _ = try await store.query(MemoryQuery(limit: 0))
        }

        await #expect(throws: MemoryError.invalidQuery("Limit must be greater than zero")) {
            _ = try await store.query(MemoryQuery(limit: -5))
        }

        await #expect(throws: MemoryError.invalidQuery("Query minImportance must be finite and within [0.0, 1.0]")) {
            _ = try await store.query(MemoryQuery(minImportance: Double.nan))
        }

        await #expect(throws: MemoryError.invalidQuery("Query minImportance must be finite and within [0.0, 1.0]")) {
            _ = try await store.query(MemoryQuery(minImportance: Double.infinity))
        }

        await #expect(throws: MemoryError.invalidQuery("Query minImportance must be finite and within [0.0, 1.0]")) {
            _ = try await store.query(MemoryQuery(minImportance: -0.1))
        }

        await #expect(throws: MemoryError.invalidQuery("Query minImportance must be finite and within [0.0, 1.0]")) {
            _ = try await store.query(MemoryQuery(minImportance: 1.05))
        }
    }

    @Test func exactTokenLookupAndNonexistentToken() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(id: MemoryRecordID(rawValue: "rec-1"), kind: .fact, content: "Quantum computing algorithms", provenance: Provenance(source: "user"))
        let r2 = MemoryRecord(id: MemoryRecordID(rawValue: "rec-2"), kind: .fact, content: "Classical mechanics physics", provenance: Provenance(source: "user"))

        try await store.bulkInsert([r1, r2])

        // Exact token match
        let queryExact = MemoryQuery(textSearch: "quantum")
        let resultExact = try await store.query(queryExact)
        #expect(resultExact.records.count == 1)
        #expect(resultExact.records.first?.id.rawValue == "rec-1")

        // Nonexistent token returns no match
        let queryNone = MemoryQuery(textSearch: "thermodynamics")
        let resultNone = try await store.query(queryNone)
        #expect(resultNone.records.isEmpty)
    }

    @Test func multiTokenQueryMatchesAndRanksCandidates() async throws {
        let store = InMemoryMemoryStore()

        let r1 = MemoryRecord(id: MemoryRecordID(rawValue: "multi-1"), kind: .fact, content: "Swift language overview", provenance: Provenance(source: "a"), importance: 0.5)
        let r2 = MemoryRecord(id: MemoryRecordID(rawValue: "multi-2"), kind: .fact, content: "Swift concurrency language features", provenance: Provenance(source: "a"), importance: 0.5)

        try await store.bulkInsert([r1, r2])

        let query = MemoryQuery(textSearch: "swift concurrency", sortOrder: .relevance)
        let result = try await store.query(query)

        #expect(result.records.count == 2)
        #expect(result.records[0].id.rawValue == "multi-2")
    }

    @Test func recordUpdateRemovesOldTokenAndAddsNewTokenInIndex() async throws {
        let store = InMemoryMemoryStore()

        let original = MemoryRecord(id: MemoryRecordID(rawValue: "upd-1"), kind: .fact, content: "Original alpha content", provenance: Provenance(source: "user"), version: 1)
        try await store.capture(original)

        // Verify initial token matches
        #expect((try await store.query(MemoryQuery(textSearch: "alpha"))).records.count == 1)
        #expect((try await store.query(MemoryQuery(textSearch: "beta"))).records.isEmpty)

        // Update content to replace "alpha" with "beta"
        let updated = original.updating(content: "Updated beta content")
        try await store.update(updated)

        // Old token "alpha" must no longer match, new token "beta" must match
        #expect((try await store.query(MemoryQuery(textSearch: "alpha"))).records.isEmpty)
        let newMatch = try await store.query(MemoryQuery(textSearch: "beta"))
        #expect(newMatch.records.count == 1)
        #expect(newMatch.records.first?.content == "Updated beta content")
    }

    @Test func fileBackedStoreReloadRebuildsTextIndexCorrectly() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4TextReload_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try FileBackedMemoryStore(directoryURL: tempDir)
        let rec = MemoryRecord(kind: .fact, content: "Persistent memory index test", provenance: Provenance(source: "user"))
        try await store.capture(rec)

        // Re-read/reload store from disk
        try await store.reload()

        let query = MemoryQuery(textSearch: "persistent")
        let result = try await store.query(query)

        #expect(result.records.count == 1)
        #expect(result.records.first?.content == "Persistent memory index test")
    }

    @Test func partialTokenQueryReturnsZeroMatchesInExactTokenSearch() async throws {
        let store = InMemoryMemoryStore()

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-exact-only"),
            kind: .fact,
            content: "Quantum computing algorithms",
            provenance: Provenance(source: "user")
        )
        try await store.capture(record)

        // Querying partial token "comput" must return 0 matches against "computing"
        let partialQuery = MemoryQuery(textSearch: "comput")
        let partialResult = try await store.query(partialQuery)
        #expect(partialResult.records.isEmpty)

        // Querying full exact token "computing" must return 1 match
        let exactQuery = MemoryQuery(textSearch: "computing")
        let exactResult = try await store.query(exactQuery)
        #expect(exactResult.records.count == 1)
        #expect(exactResult.records.first?.id.rawValue == "rec-exact-only")
    }

    @Test func candidateSelectionAndMatchesFiltersAgreeOnExactTokenSemantics() async throws {
        let store = InMemoryMemoryStore()

        let rec = MemoryRecord(
            id: MemoryRecordID(rawValue: "rec-foobar"),
            kind: .fact,
            content: "foobar baz",
            provenance: Provenance(source: "user")
        )
        try await store.capture(rec)

        // Path 1: Text query candidate index lookup for "foo"
        let indexQuery = MemoryQuery(textSearch: "foo")
        let indexResult = try await store.query(indexQuery)
        #expect(indexResult.records.isEmpty)

        // Path 2: Direct ID query with textSearch filter for "foo" (bypasses candidateIDs index, tests matchesFilters directly)
        let directFilterQuery = MemoryQuery(ids: [rec.id], textSearch: "foo")
        let directFilterResult = try await store.query(directFilterQuery)
        #expect(directFilterResult.records.isEmpty)

        // Path 3: Direct ID query with exact token textSearch "foobar"
        let exactFilterQuery = MemoryQuery(ids: [rec.id], textSearch: "foobar")
        let exactFilterResult = try await store.query(exactFilterQuery)
        #expect(exactFilterResult.records.count == 1)
        #expect(exactFilterResult.records.first?.id.rawValue == "rec-foobar")
    }
}
