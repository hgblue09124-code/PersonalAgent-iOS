import Foundation
import PAFoundation
import PAEvents
import PAObservability

public protocol StorageRecord: Sendable, Codable, Equatable {
    var id: String { get }
    var updatedAt: Date { get }
    var version: Int { get }
}

public protocol LocalStore: Sendable {
    associatedtype Record: StorageRecord
    func upsert(_ record: Record) async throws
    func fetch(id: String) async throws -> Record?
    func delete(id: String) async throws
}

public protocol CloudStore: Sendable {
    associatedtype Record: StorageRecord
    func push(_ record: Record) async throws
    func pull(id: String) async throws -> Record?
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

public protocol CloudStorageProvider: Sendable {
    var identifier: String { get }
    var isAvailable: Bool { get async }
}

public enum StorageBoundary {
    public static let forbidsOverwriteWithoutConflictPolicy = true
}
