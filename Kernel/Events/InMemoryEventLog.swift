import Foundation
import PAFoundation

/// Process-local event sink. Not a persistence engine and not M8 replay storage.
public actor InMemoryEventLog: EventLog {
    private var stored: [ExecutionEvent] = []

    public init() {}

    public func append(_ event: ExecutionEvent) async throws {
        stored.append(event)
    }

    public func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        stored.filter { $0.traceID == traceID }
    }

    public func allEvents() async -> [ExecutionEvent] {
        stored
    }

    public func kinds() async -> [ExecutionEventKind] {
        stored.map(\.kind)
    }
}
