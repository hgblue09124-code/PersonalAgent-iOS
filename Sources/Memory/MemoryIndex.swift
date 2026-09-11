import Foundation
import PAFoundation

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

        // Remove old entry if updating
        if idMap[id] != nil {
            removeIndexes(for: id)
        }

        idMap[id] = record

        // Scope index
        scopeIndex[record.scope, default: []].insert(id)

        // Kind index
        kindIndex[record.kind, default: []].insert(id)

        // Lifecycle index
        lifecycleIndex[record.lifecycle, default: []].insert(id)

        // Metadata index
        for (key, val) in record.metadata.storage {
            var valMap = metadataIndex[key, default: [:]]
            var idSet = valMap[val, default: []]
            idSet.insert(id)
            valMap[val] = idSet
            metadataIndex[key] = valMap
        }

        // Inverted word index for text matching
        let tokens = tokenize(record.content)
        for token in tokens {
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
        Array(idMap.values)
    }

    public func count(scope: MemoryScope?) -> Int {
        if let scope {
            return scopeIndex[scope]?.count ?? 0
        }
        return idMap.count
    }

    public func query(_ query: MemoryQuery) -> MemoryQueryResult {
        let startTime = DispatchTime.now().uptimeNanoseconds

        // If specific IDs are requested, perform direct O(1) lookups
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

        // Use index set intersection where possible
        var candidateIDs: Set<MemoryRecordID>?

        // Scope filter candidate set
        if let scopes = query.scopes, !scopes.isEmpty {
            var scopeSet = Set<MemoryRecordID>()
            for s in scopes {
                if let set = scopeIndex[s] {
                    scopeSet.formUnion(set)
                }
            }
            candidateIDs = scopeSet
        }

        // Kind filter candidate set
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

        // Lifecycle filter candidate set
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

        // Text search candidate set (OR union across tokens using direct O(1) posting set lookup)
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

        // Metadata filters candidate set
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

        // Collect records for candidates or all records if no set filter was active
        let finalCandidateRecords: [MemoryRecord]
        if let candidateIDs {
            finalCandidateRecords = candidateIDs.compactMap { idMap[$0] }
        } else {
            finalCandidateRecords = Array(idMap.values)
        }

        // Apply remaining scalar/range predicate filtering
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
        if let scopes = query.scopes, !scopes.contains(record.scope) {
            return false
        }
        if let kinds = query.kinds, !kinds.contains(record.kind) {
            return false
        }
        if let lifecycles = query.lifecycles, !lifecycles.contains(record.lifecycle) {
            return false
        }
        if let startDate = query.startDate, record.createdAt < startDate {
            return false
        }
        if let endDate = query.endDate, record.createdAt > endDate {
            return false
        }
        if let minImportance = query.minImportance, record.importance < minImportance {
            return false
        }
        if let metaFilters = query.metadataFilters {
            for (k, v) in metaFilters {
                if record.metadata[k] != v {
                    return false
                }
            }
        }
        if let textSearch = query.textSearch, !textSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let recordTokens = Set(tokenize(record.content))
            let searchTokens = tokenize(textSearch)
            var hasMatch = false
            for st in searchTokens {
                if recordTokens.contains(st) {
                    hasMatch = true
                    break
                }
            }
            if !hasMatch {
                return false
            }
        }
        return true
    }

    private func sortAndLimit(_ records: [MemoryRecord], query: MemoryQuery) -> [MemoryRecord] {
        let sorted: [MemoryRecord]
        switch query.sortOrder {
        case .createdAtDescending:
            sorted = records.sorted { $0.createdAt > $1.createdAt }
        case .createdAtAscending:
            sorted = records.sorted { $0.createdAt < $1.createdAt }
        case .importanceDescending:
            sorted = records.sorted {
                if $0.importance != $1.importance {
                    return $0.importance > $1.importance
                }
                return $0.createdAt > $1.createdAt
            }
        case .relevance:
            if let textSearch = query.textSearch, !textSearch.isEmpty {
                let searchTokens = tokenize(textSearch)
                sorted = records.sorted { r1, r2 in
                    let score1 = computeRelevance(r1, tokens: searchTokens)
                    let score2 = computeRelevance(r2, tokens: searchTokens)
                    if score1 != score2 {
                        return score1 > score2
                    }
                    return r1.createdAt > r2.createdAt
                }
            } else {
                sorted = records.sorted {
                    if $0.importance != $1.importance {
                        return $0.importance > $1.importance
                    }
                    return $0.createdAt > $1.createdAt
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
        for token in tokens {
            if recordTokens.contains(token) {
                matchCount += 1.0
            }
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

        let tokens = tokenize(old.content)
        for token in tokens {
            invertedWordIndex[token]?.remove(id)
        }
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
