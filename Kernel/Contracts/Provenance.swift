
import Foundation

public struct Provenance: Hashable, Sendable, Codable {
    public let source: String
    public let recordedAt: Date

    public init(source: String, recordedAt: Date = Date()) {
        self.source = source
        self.recordedAt = recordedAt
    }
}
