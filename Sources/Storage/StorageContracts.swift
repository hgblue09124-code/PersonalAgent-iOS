import Foundation

/// Errors that can occur during cloud storage operations.
public enum CloudStorageError: Error, Equatable, Sendable {
    case unavailable(String)
    case storeFailed(String)
    case conflict(String)
    case unauthorized(String)
}

/// Boundary constant assertions for storage contract guarantees.
public enum StorageBoundary {
    public static let forbidsOverwriteWithoutConflictPolicy = true
}

/// A protocol representing a storage record across local and cloud stores.
public protocol StorageRecord: Equatable, Sendable, Codable {
    var id: String { get }
    var version: Int { get }
    var parentVersion: Int? { get }
    var revisionToken: String { get }
    var parentRevisionToken: String? { get }
    var ancestorRevisionTokens: Set<String> { get }
    var updatedAt: Date { get }

    /// Creates a copy of this record with updated lineage metadata.
    func updatingVersion(
        _ newVersion: Int,
        parentVersion: Int?,
        revisionToken: String,
        parentRevisionToken: String?,
        ancestorRevisionTokens: Set<String>
    ) -> Self

    /// Determines if this record is a proven descendant of an ancestor record.
    /// Direct check strictly verifies candidate.version == ancestor.version + 1.
    func isDescendant(of ancestor: Self) -> Bool
}

extension StorageRecord {
    public func isDescendant(of ancestor: Self) -> Bool {
        guard self.id == ancestor.id else { return false }
        guard self.version > ancestor.version else { return false }

        // Must have non-empty revision tokens
        guard !self.revisionToken.isEmpty, !ancestor.revisionToken.isEmpty else { return false }

        // Revision token identity uniqueness invariant: revision tokens must not match across revisions
        guard self.revisionToken != ancestor.revisionToken else { return false }

        // Direct parent-child relationship strictly required for standalone pair evaluation
        guard self.version == ancestor.version + 1 else {
            return false
        }

        // Must have matching parentVersion
        guard let pVer = self.parentVersion, pVer == ancestor.version else {
            return false
        }

        // Must have matching parentRevisionToken
        guard let pToken = self.parentRevisionToken, !pToken.isEmpty, pToken == ancestor.revisionToken else {
            return false
        }

        // Cyclic token check: revisionToken cannot equal parentRevisionToken
        guard self.revisionToken != pToken else {
            return false
        }

        return true
    }
}

/// Explicit representation of lineage verification results.
public enum LineageProofResult: Sendable, Equatable {
    case provenDescendant
    case notDescendant
    case unprovenGap(requiredVersionRange: ClosedRange<Int>)
    case corruptHistory(String)
}

/// Vendor-agnostic protocol for retrieving authoritative historical revisions of a record.
public protocol RevisionHistoryStore<Record>: Sendable {
    associatedtype Record: StorageRecord

    /// Fetches a specific historical revision of record `id` at `version`.
    /// Throws an error if duplicate or conflicting records exist for `(id, version)`.
    /// Returns `nil` if no committed historical revision exists at `version`.
    func fetchRevision(id: String, version: Int) async throws -> Record?
}

/// Protocol for explicit lineage verification across single or multi-generation version steps.
public protocol LineageVerifying<Record>: Sendable {
    associatedtype Record: StorageRecord

    /// Verifies whether `candidate` is a proven descendant of `ancestor`.
    func verifyLineage(candidate: Record, ancestor: Record) async -> LineageProofResult
}

/// Reference implementation performing store-backed intermediate lineage verification.
public final class DefaultLineageVerifier<History: RevisionHistoryStore>: LineageVerifying, Sendable {
    public typealias Record = History.Record
    private let historyStore: History

    public init(historyStore: History) {
        self.historyStore = historyStore
    }

    public func verifyLineage(candidate: Record, ancestor: Record) async -> LineageProofResult {
        guard candidate.id == ancestor.id else { return .notDescendant }
        guard candidate.version > ancestor.version else { return .notDescendant }
        guard !candidate.revisionToken.isEmpty, !ancestor.revisionToken.isEmpty else { return .notDescendant }
        guard candidate.revisionToken != ancestor.revisionToken else {
            return .corruptHistory("Shared revision token between candidate and ancestor: \(candidate.revisionToken)")
        }

        // Direct parent step evaluation
        if candidate.version == ancestor.version + 1 {
            guard candidate.parentVersion == ancestor.version else { return .notDescendant }
            guard let pToken = candidate.parentRevisionToken, !pToken.isEmpty, pToken == ancestor.revisionToken else {
                return .notDescendant
            }
            guard candidate.revisionToken != pToken else {
                return .corruptHistory("Cyclic revision token: \(candidate.revisionToken)")
            }
            return .provenDescendant
        }

        // Multi-generation version gap evaluation (candidate.version > ancestor.version + 1)
        var currentTarget = candidate

        for v in stride(from: candidate.version - 1, through: ancestor.version, by: -1) {
            let fetched: Record?
            do {
                fetched = try await historyStore.fetchRevision(id: candidate.id, version: v)
            } catch {
                return .corruptHistory("Duplicate or conflicting revisions at version \(v): \(error.localizedDescription)")
            }

            guard let fetchedRecord = fetched else {
                return .unprovenGap(requiredVersionRange: (ancestor.version + 1)...(candidate.version - 1))
            }

            // Token identity check
            guard fetchedRecord.revisionToken != currentTarget.revisionToken else {
                return .corruptHistory("Shared revision token across versions: \(fetchedRecord.revisionToken)")
            }

            // Step-wise linkage check
            guard currentTarget.parentVersion == fetchedRecord.version else {
                return .notDescendant
            }
            guard let pToken = currentTarget.parentRevisionToken, !pToken.isEmpty, pToken == fetchedRecord.revisionToken else {
                return .notDescendant
            }
            guard currentTarget.revisionToken != pToken else {
                return .corruptHistory("Cyclic revision token: \(currentTarget.revisionToken)")
            }

            currentTarget = fetchedRecord
        }

        if currentTarget.version == ancestor.version && currentTarget.revisionToken == ancestor.revisionToken {
            return .provenDescendant
        } else {
            return .notDescendant
        }
    }
}

/// Protocol defining a cloud storage provider adapter interface.
public protocol CloudStorageProvider: Sendable {
    var identifier: String { get }
    var isAvailable: Bool { get async }
}

/// A reference implementation of an abstract cloud storage provider.
public final class AbstractCloudStorageProvider: CloudStorageProvider, @unchecked Sendable {
    public let identifier: String
    private var _isAvailable: Bool

    public init(identifier: String, isAvailable: Bool = true) {
        self.identifier = identifier
        self._isAvailable = isAvailable
    }

    public var isAvailable: Bool {
        get async { _isAvailable }
    }

    public func setAvailable(_ available: Bool) {
        self._isAvailable = available
    }
}

/// Protocol defining operations for a local storage engine.
public protocol LocalStore<Record>: Sendable {
    associatedtype Record: StorageRecord

    func fetch(id: String) async throws -> Record?
    func upsert(_ record: Record) async throws
    func forget(id: String) async throws
}

/// Protocol defining operations for a remote cloud storage engine.
public protocol CloudStore<Record>: Sendable {
    associatedtype Record: StorageRecord

    var provider: any CloudStorageProvider { get }

    func push(_ record: Record) async throws
    func pull(id: String) async throws -> Record?
}

/// A reference implementation of an in-memory cloud store.
public actor InMemoryCloudStore<Record: StorageRecord>: CloudStore {
    public let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]

    public init(provider: any CloudStorageProvider) {
        self.provider = provider
    }

    public func push(_ record: Record) async throws {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is unavailable")
        }
        records[record.id] = record
    }

    public func pull(id: String) async throws -> Record? {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is unavailable")
        }
        return records[id]
    }
}

/// Policy for resolving conflicts between local and remote records.
public enum ConflictResolution: String, Sendable, Codable {
    case keepLocal
    case keepRemote
    case merge
    case requireUser
}

/// Value object representing a sync conflict between a local and remote record.
public struct SyncConflict<Record: StorageRecord>: Sendable, Equatable {
    public let local: Record
    public let remote: Record

    public init(local: Record, remote: Record) {
        self.local = local
        self.remote = remote
    }
}

/// Protocol defining local <-> cloud sync orchestration.
public protocol SyncEngine: Sendable {
    associatedtype Record: StorageRecord

    func enqueueLocalChange(id: String) async throws
    func synchronize() async throws
    func pendingConflicts() async -> [SyncConflict<Record>]
    func resolve(_ conflict: SyncConflict<Record>, policy: ConflictResolution) async throws
}
