import Foundation
import PAFoundation
import PAObservability

public actor InMemoryEventLog: EventLog {
    private var events: [ExecutionEvent] = []

    public init() {}

    public func append(_ event: ExecutionEvent) async {
        events.append(event)
    }

    public func all() async -> [ExecutionEvent] {
        events
    }
}
