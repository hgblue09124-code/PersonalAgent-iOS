import Foundation
import PAKernel

/// Thread-safe in-memory index structures for sub-millisecond query performance.
public struct MemoryIndex: Sendable {
    private var idMap: [MemoryRecordID: MemoryRecord] = [:]
    private var scopeIndex: [MemoryScope: Set<MemoryRecordID>] = [:]
    private var kindIndex: [MemoryKind: Set<MemoryRecordID>] = [:]
    private var lifecycleIndex: [MemoryLifecycle: Set<MemoryRecordID>] = [:]
    private var metadataIndex: [String: [String: Set<MemoryRecordID>]] = [:]
    private var invertedWordIndex: [String: Set<MemoryRecordID>] = [:]

    public init() {}

    public var count: Int { idMap.count }

    public mutating func index(_ record: MemoryRecord) {
        let id = record.id
        if idMap[id] != nil {
            removeIndexes(for: id)
        }
        idMap[id] = record
        scopeIndex[record.scope, default: []].insert(id)
        kindIndex[record.kind, default: []].insert(id)
        lifecycleIndex[record.lifecycle, default: []].insert(id)

        for (key, val) in record.metadata.storage {
            var valMap = metadataIndex[key, default: [:]]
            var idSet = valMap[val, default: []]
            idSet.insert(id)
            valMap[val] = idSet
            metadataIndex[key] = valMap
        }

        for token in tokenize(record.content) {
            invertedWordIndex[token, default: []].insert(id)
        }
    }

    public mutating func remove(id: MemoryRecordID) {
        removeIndexes(for: id)
        idMap.removeValue(forKey: id)
    }

    public mutating func clear() {
        idMap.removeAll(keepingCapacity: true)
        scopeIndex.removeAll(keepingCapacity: true)
        kindIndex.removeAll(keepingCapacity: true)
        lifecycleIndex.removeAll(keepingCapacity: true)
        metadataIndex.removeAll(keepingCapacity: true)
        invertedWordIndex.removeAll(keepingCapacity: true)
    }

    public func record(for id: MemoryRecordID) -> MemoryRecord? {
        idMap[id]
    }

    public func allRecords() -> [MemoryRecord] {
        idMap.values.sorted { lhs, rhs in
            lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public func count(scope: MemoryScope?) -> Int {
        if let scope {
            return scopeIndex[scope]?.count ?? 0
        }
        return idMap.count
    }

    public func query(_ query: MemoryQuery) -> MemoryQueryResult {
        let startTime = DispatchTime.now().uptimeNanoseconds

        if let requestedIDs = query.ids {
            var matched: [MemoryRecord] = []
            for id in requestedIDs {
                if let rec = idMap[id], matchesFilters(rec, query: query) {
                    matched.append(rec)
                }
            }
            let sorted = sortAndLimit(matched, query: query)
            let duration = DispatchTime.now().uptimeNanoseconds - startTime
            return MemoryQueryResult(
                records: sorted,
                totalCount: matched.count,
                executionDurationNanoseconds: duration
            )
        }

        var candidateIDs: Set<MemoryRecordID>?

        if let scopes = query.scopes, !scopes.isEmpty {
            var scopeSet = Set<MemoryRecordID>()
            for s in scopes {
                if let set = scopeIndex[s] {
                    scopeSet.formUnion(set)
                }
            }
            candidateIDs = scopeSet
        }

        if let kinds = query.kinds, !kinds.isEmpty {
            var kindSet = Set<MemoryRecordID>()
            for k in kinds {
                if let set = kindIndex[k] {
                    kindSet.formUnion(set)
                }
            }
            if let current = candidateIDs {
                candidateIDs = current.intersection(kindSet)
            } else {
                candidateIDs = kindSet
            }
        }

        if let lifecycles = query.lifecycles, !lifecycles.isEmpty {
            var lcSet = Set<MemoryRecordID>()
            for lc in lifecycles {
                if let set = lifecycleIndex[lc] {
                    lcSet.formUnion(set)
                }
            }
            if let current = candidateIDs {
                candidateIDs = current.intersection(lcSet)
            } else {
                candidateIDs = lcSet
            }
        }

        if let textSearch = query.textSearch, !textSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tokens = tokenize(textSearch)
            if !tokens.isEmpty {
                var textMatchedIDs = Set<MemoryRecordID>()
                for token in tokens {
                    if let ids = invertedWordIndex[token] {
                        textMatchedIDs.formUnion(ids)
                    }
                }
                if let current = candidateIDs {
                    candidateIDs = current.intersection(textMatchedIDs)
                } else {
                    candidateIDs = textMatchedIDs
                }
            }
        }

        if let metaFilters = query.metadataFilters, !metaFilters.isEmpty {
            for (key, val) in metaFilters {
                let metaSet = metadataIndex[key]?[val] ?? []
                if let current = candidateIDs {
                    candidateIDs = current.intersection(metaSet)
                } else {
                    candidateIDs = metaSet
                }
            }
        }

        let finalCandidateRecords: [MemoryRecord]
        if let candidateIDs {
            finalCandidateRecords = candidateIDs.compactMap { idMap[$0] }
        } else {
            finalCandidateRecords = Array(idMap.values)
        }

        let matchedRecords = finalCandidateRecords.filter { matchesFilters($0, query: query) }
        let sortedRecords = sortAndLimit(matchedRecords, query: query)

        let duration = DispatchTime.now().uptimeNanoseconds - startTime
        return MemoryQueryResult(
            records: sortedRecords,
            totalCount: matchedRecords.count,
            executionDurationNanoseconds: duration
        )
    }

    private func matchesFilters(_ record: MemoryRecord, query: MemoryQuery) -> Bool {
        if let scopes = query.scopes, !scopes.contains(record.scope) { return false }
        if let kinds = query.kinds, !kinds.contains(record.kind) { return false }
        if let lifecycles = query.lifecycles {
            if !lifecycles.contains(record.lifecycle) { return false }
        } else if record.lifecycle == .deleted {
            // A forgotten record is a tombstone for revision/audit purposes, not retrievable memory.
            return false
        }
        if let startDate = query.startDate, record.createdAt < startDate { return false }
        if let endDate = query.endDate, record.createdAt > endDate { return false }
        if let minImportance = query.minImportance, record.importance < minImportance { return false }

        if let metaFilters = query.metadataFilters {
            for (k, v) in metaFilters where record.metadata[k] != v {
                return false
            }
        }

        if let textSearch = query.textSearch, !textSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let recordTokens = Set(tokenize(record.content))
            let searchTokens = tokenize(textSearch)
            guard !searchTokens.isEmpty else { return true }
            guard searchTokens.contains(where: recordTokens.contains) else { return false }
        }
        return true
    }

    private func sortAndLimit(_ records: [MemoryRecord], query: MemoryQuery) -> [MemoryRecord] {
        let sorted: [MemoryRecord]
        switch query.sortOrder {
        case .createdAtDescending:
            sorted = records.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.rawValue < $1.id.rawValue
            }
        case .createdAtAscending:
            sorted = records.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.rawValue < $1.id.rawValue
            }
        case .importanceDescending:
            sorted = records.sorted {
                if $0.importance != $1.importance { return $0.importance > $1.importance }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.rawValue < $1.id.rawValue
            }
        case .relevance:
            if let textSearch = query.textSearch, !textSearch.isEmpty {
                let searchTokens = tokenize(textSearch)
                sorted = records.sorted { r1, r2 in
                    let score1 = computeRelevance(r1, tokens: searchTokens)
                    let score2 = computeRelevance(r2, tokens: searchTokens)
                    if score1 != score2 { return score1 > score2 }
                    if r1.createdAt != r2.createdAt { return r1.createdAt > r2.createdAt }
                    return r1.id.rawValue < r2.id.rawValue
                }
            } else {
                sorted = records.sorted {
                    if $0.importance != $1.importance { return $0.importance > $1.importance }
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.rawValue < $1.id.rawValue
                }
            }
        }

        if let limit = query.limit, limit > 0, sorted.count > limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    private func computeRelevance(_ record: MemoryRecord, tokens: [String]) -> Double {
        let recordTokens = Set(tokenize(record.content))
        var matchCount = 0.0
        for token in tokens where recordTokens.contains(token) {
            matchCount += 1.0
        }
        return matchCount + (record.importance * 0.5)
    }

    private mutating func removeIndexes(for id: MemoryRecordID) {
        guard let old = idMap[id] else { return }

        scopeIndex[old.scope]?.remove(id)
        kindIndex[old.kind]?.remove(id)
        lifecycleIndex[old.lifecycle]?.remove(id)

        for (key, val) in old.metadata.storage {
            metadataIndex[key]?[val]?.remove(id)
        }

        for token in tokenize(old.content) {
            invertedWordIndex[token]?.remove(id)
        }
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
