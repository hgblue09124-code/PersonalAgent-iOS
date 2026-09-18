import Testing
import Foundation
import PAFoundation
import PAKernel
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PAComposition

struct TestEvidenceResolver: ExecutionEvidenceResolver {
    let mode: Mode

    enum Mode {
        case completed(ExecutionReceipt)
        case notStarted
        case unknown
        case unavailable
        case throwing
    }

    func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
        switch mode {
        case .completed(let receipt):
            return .completed(receipt)
        case .notStarted:
            return .notStarted
        case .unknown:
            return .unknown
        case .unavailable:
            return .unavailable
        case .throwing:
            struct ResolverError: Error {}
            throw ResolverError()
        }
    }
}

@Suite("M7 Recovery Tests")
struct M7RecoveryTests {

    @Test("STARTED_UNKNOWN attempt resolved as completed")
    func testRecoveryStartedUnknownCompleted() async throws {
        let attemptID = ExecutionAttemptID()
        let toolID = ToolID(rawValue: "echo")
        let receipt = ExecutionReceipt(
            attemptID: attemptID,
            toolID: toolID,
            idempotencyKey: "key-1",
            outputSummary: "Recovered receipt summary"
        )
        let resolver = TestEvidenceResolver(mode: .completed(receipt))

        let composition = try await M7CompositionRoot(evidenceResolver: resolver)
        let goal = Goal(statement: "Recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        // Inject STARTED_UNKNOWN attempt
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            toolID: toolID,
            idempotencyKey: "key-1",
            status: .startedUnknown
        )
        try await composition.attemptStore.saveAttempt(attempt)

        let outcome = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        if case .resumed(let rec) = outcome {
            #expect(rec.status == .running)
        } else {
            #expect(Bool(false), "Expected resumed outcome, got \(outcome)")
        }

        let updatedAttempt = try await composition.attemptStore.attempt(for: attemptID)
        #expect(updatedAttempt?.status == .completed)
        #expect(updatedAttempt?.receiptRef == receipt.receiptID)
    }

    @Test("STARTED_UNKNOWN attempt resolved as notStarted")
    func testRecoveryStartedUnknownNotStarted() async throws {
        let resolver = TestEvidenceResolver(mode: .notStarted)

        let composition = try await M7CompositionRoot(evidenceResolver: resolver)
        let goal = Goal(statement: "Recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            idempotencyKey: "key-2",
            status: .startedUnknown
        )
        try await composition.attemptStore.saveAttempt(attempt)

        let outcome = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        if case .resumed(let rec) = outcome {
            #expect(rec.status == .running)
        } else {
            #expect(Bool(false), "Expected resumed outcome, got \(outcome)")
        }

        let updatedAttempt = try await composition.attemptStore.attempt(for: attemptID)
        #expect(updatedAttempt?.status == .notStarted)
    }

    @Test("STARTED_UNKNOWN attempt resolved as unknown halts run as interrupted")
    func testRecoveryStartedUnknownUnknownHaltsInterrupted() async throws {
        let resolver = TestEvidenceResolver(mode: .unknown)

        let composition = try await M7CompositionRoot(evidenceResolver: resolver)
        let goal = Goal(statement: "Recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            idempotencyKey: "key-3",
            status: .startedUnknown
        )
        try await composition.attemptStore.saveAttempt(attempt)

        let outcome = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        if case .interrupted(let rec, _) = outcome {
            #expect(rec.status == .interrupted)
        } else {
            #expect(Bool(false), "Expected interrupted outcome, got \(outcome)")
        }

        let updatedAttempt = try await composition.attemptStore.attempt(for: attemptID)
        #expect(updatedAttempt?.status == .unresolved)
    }

    @Test("STARTED_UNKNOWN attempt with throwing resolver maps to unavailable and halts interrupted")
    func testRecoveryThrowingResolverMapsToUnavailable() async throws {
        let resolver = TestEvidenceResolver(mode: .throwing)

        let composition = try await M7CompositionRoot(evidenceResolver: resolver)
        let goal = Goal(statement: "Recovery test throwing resolver")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            idempotencyKey: "key-4",
            status: .startedUnknown
        )
        try await composition.attemptStore.saveAttempt(attempt)

        let outcome = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        if case .interrupted(let rec, _) = outcome {
            #expect(rec.status == .interrupted)
        } else {
            #expect(Bool(false), "Expected interrupted outcome, got \(outcome)")
        }

        let updatedAttempt = try await composition.attemptStore.attempt(for: attemptID)
        #expect(updatedAttempt?.status == .unresolved)
    }

    @Test("WAL state journal recovery replays state update event with stable EventID")
    func testStateJournalRecoveryReplaysEventLog() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "WAL recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let eventID = EventID()

        // Inject pending journal entry in stateCommitted status
        let entry = StateJournalEntry(
            runID: record.runID,
            goalID: goal.id,
            targetStatus: .completed,
            eventID: eventID,
            canonicalEventPayload: "goalID=\(goal.id.rawValue)&disposition=complete",
            status: .stateCommitted
        )
        try await composition.journalStore.saveEntry(entry)

        try await composition.recoveryEngine.recoverStateJournal(runID: record.runID, traceID: record.traceID)

        let updatedEntry = try await composition.journalStore.entry(for: entry.journalID)
        #expect(updatedEntry?.status == .finalized)

        let events = try await composition.eventLog.events(for: record.traceID)
        #expect(events.contains { $0.id == eventID })
    }

    @Test("Recovery reconciles cleanly with already-completed or already-aborted goal")
    func testRecoveryReconcilesWithCompletedOrAbortedGoal() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Reconcile test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        try await composition.runtime.complete(goalID: goal.id)

        let outcome = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        if case .completed(let rec) = outcome {
            #expect(rec.status == .completed)
        } else {
            #expect(Bool(false), "Expected completed outcome, got \(outcome)")
        }
    }
}
