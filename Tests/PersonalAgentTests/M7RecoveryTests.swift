import PARuntime
import Testing
import Foundation
import PAFoundation
import PAKernel
import PAEvents
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
        let cap = ExecutionTargetCapability(toolID: toolID, idempotencyClass: .idempotent, supportsEvidenceResolution: true)

        let composition = try await M7CompositionRoot(
            evidenceResolver: resolver,
            targetCapabilities: [cap]
        )
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
        let toolID = ToolID(rawValue: "echo")
        let resolver = TestEvidenceResolver(mode: .notStarted)
        let cap = ExecutionTargetCapability(toolID: toolID, idempotencyClass: .idempotent, supportsEvidenceResolution: true)

        let composition = try await M7CompositionRoot(
            evidenceResolver: resolver,
            targetCapabilities: [cap]
        )
        let goal = Goal(statement: "Recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            toolID: toolID,
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

    @Test("STARTED_UNKNOWN for idempotent target with unknown evidence resets to NOT_STARTED")
    func testRecoveryIdempotentTargetResetsToNotStarted() async throws {
        let resolver = TestEvidenceResolver(mode: .unknown)
        let toolID = ToolID(rawValue: "idempotentTool")

        let cap = ExecutionTargetCapability(
            toolID: toolID,
            idempotencyClass: .idempotent,
            supportsEvidenceResolution: true
        )

        let composition = try await M7CompositionRoot(
            evidenceResolver: resolver,
            targetCapabilities: [cap]
        )

        let goal = Goal(statement: "Idempotent recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            toolID: toolID,
            idempotencyKey: "idempotent-key-1",
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
        #expect(updatedAttempt?.idempotencyKey == "idempotent-key-1")
    }

    @Test("STARTED_UNKNOWN for non-idempotent target with unknown evidence halts as UNRESOLVED / INTERRUPTED")
    func testRecoveryNonIdempotentTargetHaltsInterrupted() async throws {
        let resolver = TestEvidenceResolver(mode: .unknown)
        let toolID = ToolID(rawValue: "nonIdempotentTool")

        let cap = ExecutionTargetCapability(
            toolID: toolID,
            idempotencyClass: .nonIdempotent,
            supportsEvidenceResolution: true
        )

        let composition = try await M7CompositionRoot(
            evidenceResolver: resolver,
            targetCapabilities: [cap]
        )

        let goal = Goal(statement: "Non-idempotent recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            toolID: toolID,
            idempotencyKey: "non-idempotent-key-1",
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

    @Test("WAL state journal recovery reconciles when AgentRuntime state update occurred before crash")
    func testStateJournalRecoveryWhenStateAppliedBeforeCrash() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "WAL state applied test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let eventID = EventID()
        let journalID = UUID()

        // Apply state update to AgentRuntime first with required evidence and explicit mutationToken
        let update = StateUpdate(
            goalID: goal.id,
            targetStatus: .completed,
            evidence: ["disposition": "complete", "reason": "done"],
            mutationToken: journalID
        )
        try await composition.runtime.applyStateUpdate(update)

        // Inject journal entry in .prepared status
        let entry = StateJournalEntry(
            journalID: journalID,
            runID: record.runID,
            goalID: goal.id,
            targetStatus: .completed,
            eventID: eventID,
            canonicalEventPayload: IdempotentEventLog.canonicalString(for: ["disposition": "complete", "goalID": goal.id.rawValue, "reason": "done", "targetStatus": "completed"]),
            status: .prepared
        )
        try await composition.journalStore.saveEntry(entry)

        try await composition.recoveryEngine.recoverStateJournal(runID: record.runID, traceID: record.traceID)

        let updatedEntry = try await composition.journalStore.entry(for: entry.journalID)
        #expect(updatedEntry?.status == .finalized)

        let events = try await composition.eventLog.events(for: record.traceID)
        #expect(events.contains { $0.id == eventID })
    }

    @Test("WAL state journal recovery aborts journal entry when AgentRuntime state update did NOT occur before crash")
    func testStateJournalRecoveryWhenStateNotAppliedBeforeCrash() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "WAL state not applied test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let eventID = EventID()
        let journalID = UUID()

        // Inject journal entry in .prepared status, BUT AgentRuntime was never updated with mutationToken: journalID
        let entry = StateJournalEntry(
            journalID: journalID,
            runID: record.runID,
            goalID: goal.id,
            targetStatus: .completed,
            eventID: eventID,
            canonicalEventPayload: IdempotentEventLog.canonicalString(for: ["disposition": "complete", "goalID": goal.id.rawValue, "reason": "done", "targetStatus": "completed"]),
            status: .prepared
        )
        try await composition.journalStore.saveEntry(entry)

        try await composition.recoveryEngine.recoverStateJournal(runID: record.runID, traceID: record.traceID)

        let updatedEntry = try await composition.journalStore.entry(for: entry.journalID)
        #expect(updatedEntry?.status == .aborted)
    }

    @Test("Repeated recovery invocations are fully idempotent")
    func testRepeatedRecoveryIsIdempotent() async throws {
        let resolver = TestEvidenceResolver(mode: .notStarted)
        let toolID = ToolID(rawValue: "echo")
        let cap = ExecutionTargetCapability(toolID: toolID, idempotencyClass: .idempotent, supportsEvidenceResolution: true)

        let composition = try await M7CompositionRoot(
            evidenceResolver: resolver,
            targetCapabilities: [cap]
        )
        let goal = Goal(statement: "Repeated recovery test")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        let attemptID = ExecutionAttemptID()
        let attempt = ExecutionAttempt(
            attemptID: attemptID,
            runID: record.runID,
            actionID: ActionID(),
            toolID: toolID,
            idempotencyKey: "key-rep",
            status: .startedUnknown
        )
        try await composition.attemptStore.saveAttempt(attempt)

        let outcome1 = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        let outcome2 = try await composition.recoveryEngine.recoverRun(runID: record.runID)
        let outcome3 = try await composition.recoveryEngine.recoverRun(runID: record.runID)

        if case .resumed(let rec1) = outcome1,
           case .resumed(let rec2) = outcome2,
           case .resumed(let rec3) = outcome3 {
            #expect(rec1.status == .running)
            #expect(rec2.status == .running)
            #expect(rec3.status == .running)
            #expect(rec1.runID == rec2.runID)
            #expect(rec2.runID == rec3.runID)
        } else {
            #expect(Bool(false), "Expected resumed outcome across repeated recovery invocations")
        }
    }

    @Test("Restart recovery across fresh store instances using FileBacked stores")
    func testRestartRecoveryAcrossFreshStoreInstances() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let toolID = ToolID(rawValue: "echo")
        let receipt = ExecutionReceipt(
            receiptID: "r-restart-1",
            attemptID: ExecutionAttemptID(),
            toolID: toolID,
            idempotencyKey: "restart-key-1",
            outputSummary: "Success"
        )

        let runID: RunID
        let attemptID: ExecutionAttemptID = receipt.attemptID
        let goal = Goal(statement: "Durable restart goal")

        // Instance A
        do {
            let resolverA = TestEvidenceResolver(mode: .completed(receipt))
            let capA = ExecutionTargetCapability(toolID: toolID, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
            let compA = try await M7CompositionRoot(
                storeDirectoryURL: tempDir,
                evidenceResolver: resolverA,
                targetCapabilities: [capA]
            )

            try await compA.runtime.submit(goal: goal)
            let record = try await compA.lifecycleManager.createRun(goalID: goal.id)
            runID = record.runID

            let attempt = ExecutionAttempt(
                attemptID: attemptID,
                runID: runID,
                actionID: ActionID(),
                toolID: toolID,
                idempotencyKey: "restart-key-1",
                status: .startedUnknown
            )
            try await compA.attemptStore.saveAttempt(attempt)
        }

        // Instance B - fresh process / stores opening same directory
        let resolverB = TestEvidenceResolver(mode: .completed(receipt))
        let capB = ExecutionTargetCapability(toolID: toolID, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let compB = try await M7CompositionRoot(
            storeDirectoryURL: tempDir,
            evidenceResolver: resolverB,
            targetCapabilities: [capB]
        )
        try await compB.runtime.submit(goal: goal)

        // Verify Instance B loaded persisted attempt from Instance A
        let loadedAttempt = try await compB.attemptStore.attempt(for: attemptID)
        #expect(loadedAttempt != nil)
        #expect(loadedAttempt?.status == .startedUnknown)

        // Recover run with Instance B
        let outcome = try await compB.recoveryEngine.recoverRun(runID: runID)
        if case .resumed(let rec) = outcome {
            #expect(rec.status == .running)
        } else {
            #expect(Bool(false), "Expected resumed outcome from Instance B recovery, got \(outcome)")
        }

        let updatedAttempt = try await compB.attemptStore.attempt(for: attemptID)
        #expect(updatedAttempt?.status == .completed)
        #expect(updatedAttempt?.receiptRef == receipt.receiptID)
    }

    @Test("Persistence errors throw and fail closed without false successful transition")
    func testPersistenceFailureFailsClosed() async throws {
        let invalidDir = URL(fileURLWithPath: "/dev/null/invalid_dir_\(UUID().uuidString)")
        do {
            _ = try FileBackedRunStore(directoryURL: invalidDir)
            #expect(Bool(false), "Expected FileBackedRunStore init or directory creation to throw")
        } catch {
            #expect(error != nil)
        }
    }
}
