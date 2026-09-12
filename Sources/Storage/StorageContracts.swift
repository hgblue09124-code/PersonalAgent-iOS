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
    /// Ancestry requires explicit parentVersion and parentRevisionToken matching or ancestorRevisionTokens membership.
    func isDescendant(of ancestor: Self) -> Bool
}

extension StorageRecord {
    public func isDescendant(of ancestor: Self) -> Bool {
        guard self.id == ancestor.id else { return false }
        guard self.version > ancestor.version else { return false }

        // Case 1: Direct parent-child relationship
        if let pVer = self.parentVersion, pVer == ancestor.version {
            if let pToken = self.parentRevisionToken {
                return pToken == ancestor.revisionToken
            }
            return true
        }

        // Case 2: Multi-generation ancestry verified via ancestor revision tokens
        return self.ancestorRevisionTokens.contains(ancestor.revisionToken)
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
