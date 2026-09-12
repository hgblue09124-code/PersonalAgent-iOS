import Foundation
import PAFoundation
import PAEvents
import PAObservability

public protocol StorageRecord: Sendable, Codable, Equatable {
    var id: String { get }
    var updatedAt: Date { get }
    var version: Int { get }
    var parentVersion: Int? { get }

    func isDescendant(of ancestor: Self) -> Bool
    func updatingVersion(_ newVersion: Int, parentVersion: Int?) -> Self
}

public extension StorageRecord {
    func isDescendant(of ancestor: Self) -> Bool {
        guard id == ancestor.id else { return false }
        if version <= ancestor.version { return false }
        guard let parent = parentVersion else { return false }
        if parent == ancestor.version { return true }
        return false
    }
}

public protocol LocalStore: Sendable {
    associatedtype Record: StorageRecord
    func upsert(_ record: Record) async throws
    func fetch(id: String) async throws -> Record?
    func delete(id: String) async throws
}

public enum CloudStorageError: Error, Sendable, Codable, Equatable, CustomStringConvertible {
    case unavailable(String)
    case notFound(String)
    case storeFailed(String)
    case networkError(String)
    case invalidRecord(String)

    public var description: String {
        switch self {
        case .unavailable(let reason):
            return "Cloud storage unavailable: \(reason)"
        case .notFound(let id):
            return "Cloud storage record not found: \(id)"
        case .storeFailed(let reason):
            return "Cloud storage operation failed: \(reason)"
        case .networkError(let details):
            return "Cloud storage network error: \(details)"
        case .invalidRecord(let reason):
            return "Cloud storage invalid record: \(reason)"
        }
    }
}

public protocol CloudStorageProvider: Sendable {
    var identifier: String { get }
    var isAvailable: Bool { get async }
}

public protocol CloudStore: Sendable {
    associatedtype Record: StorageRecord
    var provider: any CloudStorageProvider { get }
    func push(_ record: Record) async throws
    func pull(id: String) async throws -> Record?
}

public struct AbstractCloudStorageProvider: CloudStorageProvider, Sendable {
    public let identifier: String
    private let availabilityHandler: @Sendable () async -> Bool

    public init(identifier: String, isAvailable: Bool = true) {
        self.identifier = identifier
        self.availabilityHandler = { isAvailable }
    }

    public init(identifier: String, availabilityHandler: @Sendable @escaping () async -> Bool) {
        self.identifier = identifier
        self.availabilityHandler = availabilityHandler
    }

    public var isAvailable: Bool {
        get async {
            await availabilityHandler()
        }
    }
}

public enum ConflictResolution: String, Sendable, Codable {
    case keepLocal
    case keepRemote
    case merge
    case requireUser
}

public struct SyncConflict<Record: StorageRecord>: Sendable {
    public let local: Record
    public let remote: Record

    public init(local: Record, remote: Record) {
        self.local = local
        self.remote = remote
    }
}

public protocol SyncEngine: Sendable {
    associatedtype Record: StorageRecord
    func enqueueLocalChange(id: String) async throws
    func synchronize() async throws
    func resolve(_ conflict: SyncConflict<Record>, policy: ConflictResolution) async throws
}

public enum StorageBoundary {
    public static let forbidsOverwriteWithoutConflictPolicy = true
}
