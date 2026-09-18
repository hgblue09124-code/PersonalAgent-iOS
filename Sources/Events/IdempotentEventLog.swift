import Foundation
import PAFoundation

public enum EventLogError: Error, Sendable, Equatable {
    case conflictingPayload(eventID: EventID, existing: String, new: String)
}

public actor IdempotentEventLog: EventLog {
    private let innerLog: any EventLog
    private var seenEvents: [EventID: (kind: ExecutionEventKind, payload: String)] = [:]

    public init(innerLog: any EventLog = InMemoryEventLog()) {
        self.innerLog = innerLog
    }

    public func append(_ event: ExecutionEvent) async throws {
        let canonicalPayload = canonicalString(for: event.payload)
        if let existing = seenEvents[event.id] {
            if existing.payload == canonicalPayload {
                // Idempotent success - do not duplicate in inner log
                return
            } else {
                throw EventLogError.conflictingPayload(
                    eventID: event.id,
                    existing: existing.payload,
                    new: canonicalPayload
                )
            }
        }

        try await innerLog.append(event)
        seenEvents[event.id] = (kind: event.kind, payload: canonicalPayload)
    }

    public func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        try await innerLog.events(for: traceID)
    }

    private func canonicalString(for payload: [String: String]) -> String {
        payload.keys.sorted().map { "\($0)=\(payload[$0] ?? "")" }.joined(separator: "&")
    }
}
