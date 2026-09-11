import Testing
import Foundation
import PAFoundation
import PAEvents
import PAMemory

private struct FailingEventLog: EventLog {
    struct SimulatedAppendError: Error, Equatable {}

    func append(_ event: ExecutionEvent) async throws {
        throw SimulatedAppendError()
    }

    func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        []
    }

    func allEvents() async throws -> [ExecutionEvent] {
        []
    }
}

@Suite("M4 Memory Runtime")
struct M4RuntimeTests {
    @Test func runtimeCaptureAndRetrieveRecord() async throws {
        let store = InMemoryMemoryStore()
        let eventLog = InMemoryEventLog()
        let runtime = MemoryRuntime(store: store, eventLog: eventLog)

        let record = MemoryRecord(
            kind: .fact,
            content: "User prefers Swift over C++",
            provenance: Provenance(source: "conversation"),
            scope: .agent,
            importance: 0.9
        )

        try await runtime.capture(record)

        let fetched = try await runtime.retrieve(id: record.id)
        #expect(fetched != nil)
        #expect(fetched?.id == record.id)
        #expect(fetched?.content == "User prefers Swift over C++")

        let events = try await eventLog.events(for: runtime.traceID)
        #expect(events.contains { $0.kind == .memoryCaptured })
    }

    @Test func runtimeUpdateRecordIncrementsVersionAndEmitsEvent() async throws {
        let store = InMemoryMemoryStore()
        let eventLog = InMemoryEventLog()
        let runtime = MemoryRuntime(store: store, eventLog: eventLog)

        let record = MemoryRecord(
            kind: .preference,
            content: "Dark mode enabled",
            provenance: Provenance(source: "settings")
        )

        try await runtime.capture(record)

        let updated = record.updating(content: "System dark mode enabled", importance: 1.0)
        try await runtime.update(updated)

        let fetched = try await runtime.retrieve(id: record.id)
        #expect(fetched?.content == "System dark mode enabled")
        #expect(fetched?.version == 2)

        let events = try await eventLog.events(for: runtime.traceID)
        #expect(events.contains { $0.kind == .memoryUpdated })
    }

    @Test func runtimeForgetRecordMarksLifecycleDeletedAndEmitsEvent() async throws {
        let store = InMemoryMemoryStore()
        let eventLog = InMemoryEventLog()
        let runtime = MemoryRuntime(store: store, eventLog: eventLog)

        let record = MemoryRecord(
            kind: .event,
            content: "Temporary session token",
            provenance: Provenance(source: "system")
        )

        try await runtime.capture(record)
        try await runtime.forget(id: record.id, reason: "Session expired")

        let fetched = try await runtime.retrieve(id: record.id)
        #expect(fetched?.lifecycle == .deleted)

        let events = try await eventLog.events(for: runtime.traceID)
        #expect(events.contains { $0.kind == .memoryForgotten })
    }

    @Test func runtimeFailsClosedOnDuplicateCapture() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "dup-1"),
            kind: .fact,
            content: "Fact 1",
            provenance: Provenance(source: "user")
        )

        try await runtime.capture(record)

        await #expect(throws: MemoryError.duplicateID(record.id)) {
            try await runtime.capture(record)
        }
    }

    @Test func runtimeFailsClosedOnUpdateMissingRecord() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "missing-1"),
            kind: .fact,
            content: "Fact",
            provenance: Provenance(source: "user")
        )

        await #expect(throws: MemoryError.notFound(record.id)) {
            try await runtime.update(record)
        }
    }

    @Test func runtimeRejectsInvalidImportance() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let lowImp = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: -0.1)
        let highImp = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: 1.1)
        let nanImp = MemoryRecord(kind: .fact, content: "Test", provenance: Provenance(source: "user"), importance: Double.nan)

        await #expect(throws: MemoryError.self) {
            try await runtime.capture(lowImp)
        }
        await #expect(throws: MemoryError.self) {
            try await runtime.capture(highImp)
        }
        await #expect(throws: MemoryError.self) {
            try await runtime.capture(nanImp)
        }
    }

    @Test func runtimeRejectsInvalidQueryLimits() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let qZero = MemoryQuery(limit: 0)
        let qNeg = MemoryQuery(limit: -1)

        await #expect(throws: MemoryError.self) {
            _ = try await runtime.query(qZero)
        }
        await #expect(throws: MemoryError.self) {
            _ = try await runtime.query(qNeg)
        }
        await #expect(throws: MemoryError.self) {
            _ = try await runtime.retrieve(kind: .fact, limit: 0)
        }
        await #expect(throws: MemoryError.self) {
            _ = try await runtime.retrieve(kind: .fact, limit: -1)
        }
    }

    @Test func runtimeBulkInsertAndCountAndTeardown() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let recs = (1...10).map { i in
            MemoryRecord(
                kind: .observation,
                content: "Observation \(i)",
                provenance: Provenance(source: "sensor"),
                scope: i % 2 == 0 ? .session : .agent
            )
        }

        try await runtime.bulkInsert(recs)

        let totalCount = try await runtime.count()
        let sessionCount = try await runtime.count(scope: MemoryScope.session)
        let agentCount = try await runtime.count(scope: MemoryScope.agent)

        #expect(totalCount == 10)
        #expect(sessionCount == 5)
        #expect(agentCount == 5)

        try await runtime.clear()
        let countAfterClear = try await runtime.count()
        #expect(countAfterClear == 0)
    }

    @Test func eventLoggingSuccessAppendsEventToEventLog() async throws {
        let store = InMemoryMemoryStore()
        let eventLog = InMemoryEventLog()
        let runtime = MemoryRuntime(store: store, eventLog: eventLog)

        let record = MemoryRecord(
            kind: .fact,
            content: "Testing event logging success",
            provenance: Provenance(source: "user")
        )

        try await runtime.capture(record)

        let events = try await eventLog.events(for: runtime.traceID)
        #expect(events.count == 1)
        #expect(events.first?.kind == .memoryCaptured)
    }

    @Test func eventLoggingFailurePropagatesErrorToCaller() async throws {
        let store = InMemoryMemoryStore()
        let failingLog = FailingEventLog()
        let runtime = MemoryRuntime(store: store, eventLog: failingLog)

        let record = MemoryRecord(
            kind: .fact,
            content: "Testing event logging failure propagation",
            provenance: Provenance(source: "user")
        )

        // Capture must throw the event log error rather than silently swallowing it
        await #expect(throws: FailingEventLog.SimulatedAppendError.self) {
            try await runtime.capture(record)
        }

        // Store state assertion: record IS in store (log-after-write,
        // best-effort telemetry consistency)
        let fetched = try await store.retrieve(id: record.id)
        #expect(fetched != nil)
        #expect(fetched?.id == record.id)
    }
}
