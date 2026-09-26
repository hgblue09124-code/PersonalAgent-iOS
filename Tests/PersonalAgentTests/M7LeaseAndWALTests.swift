import PARuntime
import Testing
import Foundation
import PAKernel
import PAEvents
import PAComposition

@Suite("M7 Lease and WAL Tests")
struct M7LeaseAndWALTests {

    @Test("CapabilityLease enforces atomic step consumption and maxStepCount")
    func testLeaseStepConsumptionAndMax() async throws {
        let runID = RunID()
        let lease = CapabilityLease(runID: runID, maxStepCount: 3)

        try await lease.consume(step: 1, forRunID: runID)
        let count1 = await lease.currentStepCount
        #expect(count1 == 1)

        try await lease.consume(step: 2, forRunID: runID)
        let count2 = await lease.currentStepCount
        #expect(count2 == 3)

        do {
            try await lease.consume(step: 1, forRunID: runID)
            #expect(Bool(false), "Should have thrown maxStepsExceeded")
        } catch CapabilityLeaseError.maxStepsExceeded(let current, let requested, let max) {
            #expect(current == 3)
            #expect(requested == 1)
            #expect(max == 3)
        }
    }

    @Test("CapabilityLease enforces expiration and revocation")
    func testLeaseExpirationAndRevocation() async throws {
        let runID = RunID()
        let pastDate = Date().addingTimeInterval(-10)
        let expiredLease = CapabilityLease(runID: runID, expiresAt: pastDate)

        do {
            try await expiredLease.consume(step: 1, forRunID: runID)
            #expect(Bool(false), "Should have thrown expired")
        } catch CapabilityLeaseError.expired {
            // expected
        }

        let lease = CapabilityLease(runID: runID)
        await lease.revoke()

        do {
            try await lease.consume(step: 1, forRunID: runID)
            #expect(Bool(false), "Should have thrown revoked")
        } catch CapabilityLeaseError.revoked {
            // expected
        }
    }

    @Test("CapabilityLease enforces RunID ownership isolation")
    func testLeaseRunIDMismatch() async throws {
        let runID1 = RunID()
        let runID2 = RunID()
        let lease = CapabilityLease(runID: runID1)

        do {
            try await lease.consume(step: 1, forRunID: runID2)
            #expect(Bool(false), "Should have thrown runIDMismatch")
        } catch CapabilityLeaseError.runIDMismatch(let expected, let actual) {
            #expect(expected == runID1)
            #expect(actual == runID2)
        }
    }

    @Test("IdempotentEventLog handles identical EventID idempotently")
    func testIdempotentEventLogIdenticalEventID() async throws {
        let inner = InMemoryEventLog()
        let log = IdempotentEventLog(innerLog: inner)
        let traceID = TraceID()
        let eventID = EventID()

        let event1 = ExecutionEvent(
            id: eventID,
            traceID: traceID,
            kind: .stateUpdated,
            payload: ["goalID": "g1", "status": "active"]
        )

        try await log.append(event1)
        let count1 = (await inner.allEvents()).count
        #expect(count1 == 1)

        // Re-append identical eventID + same payload
        try await log.append(event1)
        let count2 = (await inner.allEvents()).count
        #expect(count2 == 1)
    }

    @Test("IdempotentEventLog throws conflictingPayload on same EventID with conflicting payload")
    func testIdempotentEventLogConflictingPayload() async throws {
        let inner = InMemoryEventLog()
        let log = IdempotentEventLog(innerLog: inner)
        let traceID = TraceID()
        let eventID = EventID()

        let event1 = ExecutionEvent(
            id: eventID,
            traceID: traceID,
            kind: .stateUpdated,
            payload: ["goalID": "g1", "status": "active"]
        )

        let event2 = ExecutionEvent(
            id: eventID,
            traceID: traceID,
            kind: .stateUpdated,
            payload: ["goalID": "g1", "status": "completed"]
        )

        try await log.append(event1)

        do {
            try await log.append(event2)
            #expect(Bool(false), "Should have thrown conflictingPayload")
        } catch EventLogError.conflictingPayload(let id, _, _) {
            #expect(id == eventID)
        }
    }
}
