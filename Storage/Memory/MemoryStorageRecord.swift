import Foundation
import PAStorageModels
import PAMemory

public struct MemoryStorageRecord: StorageRecord, Codable, Sendable, Equatable {
    public let record: MemoryRecord

    public var id: String { record.id.rawValue }
    public var updatedAt: Date { record.updatedAt }
    public var version: Int { record.version }
    public var parentVersion: Int? { record.parentVersion }
    public var revisionToken: String { record.revisionToken }
    public var parentRevisionToken: String? { record.parentRevisionToken }
    public var ancestorRevisionTokens: Set<String> { record.ancestorRevisionTokens }

    public init(_ record: MemoryRecord) {
        self.record = record
    }

    public func updatingVersion(
        _ newVersion: Int,
        parentVersion: Int?,
        revisionToken: String,
        parentRevisionToken: String?,
        ancestorRevisionTokens: Set<String>
    ) -> MemoryStorageRecord {
        let updatedRecord = MemoryRecord(
            id: record.id,
            kind: record.kind,
            content: record.content,
            provenance: record.provenance,
            createdAt: record.createdAt,
            updatedAt: Date(),
            scope: record.scope,
            lifecycle: record.lifecycle,
            importance: record.importance,
            metadata: record.metadata,
            version: newVersion,
            parentVersion: parentVersion,
            revisionToken: revisionToken,
            parentRevisionToken: parentRevisionToken,
            ancestorRevisionTokens: ancestorRevisionTokens
        )
        return MemoryStorageRecord(updatedRecord)
    }
}
