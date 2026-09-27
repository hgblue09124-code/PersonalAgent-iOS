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
        let canonicalPayload = Self.canonicalString(for: event.payload)

        // 1. Check in-memory cache
        if let existing = seenEvents[event.id] {
            if existing.payload == canonicalPayload {
                return
            } else {
                throw EventLogError.conflictingPayload(
                    eventID: event.id,
                    existing: existing.payload,
                    new: canonicalPayload
                )
            }
        }

        // 2. Query underlying durable innerLog for fresh instances / process restarts
        let allInnerEvents = try await innerLog.allEvents()
        if let existingEvent = allInnerEvents.first(where: { $0.id == event.id }) {
            let existingPayload = Self.canonicalString(for: existingEvent.payload)
            seenEvents[event.id] = (kind: existingEvent.kind, payload: existingPayload)
            if existingPayload == canonicalPayload {
                return
            } else {
                throw EventLogError.conflictingPayload(
                    eventID: event.id,
                    existing: existingPayload,
                    new: canonicalPayload
                )
            }
        }

        // 3. Append to innerLog and update seenEvents
        try await innerLog.append(event)
        seenEvents[event.id] = (kind: event.kind, payload: canonicalPayload)
    }

    public func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        try await innerLog.events(for: traceID)
    }

    public func allEvents() async throws -> [ExecutionEvent] {
        try await innerLog.allEvents()
    }

    public static func canonicalString(for payload: [String: String]) -> String {
        let sortedKeys = payload.keys.sorted()
        let sortedPairs = sortedKeys.map { key in
            ["k": key, "v": payload[key] ?? ""]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sortedPairs, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    public static func parseCanonicalPayload(_ canonicalString: String) -> [String: String] {
        guard let data = canonicalString.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return [:]
        }
        var dict: [String: String] = [:]
        for item in jsonArray {
            if let k = item["k"], let v = item["v"] {
                dict[k] = v
            }
        }
        return dict
    }
}
