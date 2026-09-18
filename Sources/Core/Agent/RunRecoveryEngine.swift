import Foundation
import PAFoundation
import PAObservability
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules

public enum RecoveryOutcome: Sendable, Equatable {
    case resumed(RunRecord)
    case interrupted(RunRecord, reason: String)
    case failed(RunRecord, reason: String)
    case completed(RunRecord)
}

public actor RunRecoveryEngine {
    private let runtime: AgentRuntime
    private let runStore: any RunStore
    private let attemptStore: any ExecutionAttemptStore
    private let checkpointStore: any RunCheckpointStore
    private let journalStore: any StateJournalStore
    private let executionBoundary: ExecutionBoundary
    private let eventLog: any EventLog
    private let logger: any AgentLogger

    public init(
        runtime: AgentRuntime,
        runStore: any RunStore,
        attemptStore: any ExecutionAttemptStore,
        checkpointStore: any RunCheckpointStore,
        journalStore: any StateJournalStore,
        executionBoundary: ExecutionBoundary,
        eventLog: any EventLog = InMemoryEventLog(),
        logger: any AgentLogger = NullLoggerBridge()
    ) {
        self.runtime = runtime
        self.runStore = runStore
        self.attemptStore = attemptStore
        self.checkpointStore = checkpointStore
        self.journalStore = journalStore
        self.executionBoundary = executionBoundary
        self.eventLog = eventLog
        self.logger = logger
    }

    public func recoverRun(runID: RunID) async throws -> RecoveryOutcome {
        guard var record = try await runStore.record(for: runID) else {
            throw KernelError.goalNotFound(GoalID(rawValue: "unknown"))
        }

        record.status = .recovering
        record.updatedAt = Date()
        try await runStore.save(record)

        // 1. Recover pending WAL journal entries first
        try await recoverStateJournal(runID: runID, traceID: record.traceID)

        // 2. Reconcile with AgentRuntime GoalStatus
        guard let goal = await runtime.goal(id: record.goalID) else {
            record.status = .failed
            try await runStore.save(record)
            return .failed(record, reason: "Goal \(record.goalID.rawValue) not found in AgentRuntime")
        }

        if goal.status == .completed {
            record.status = .completed
            record.updatedAt = Date()
            try await runStore.save(record)
            return .completed(record)
        }

        if goal.status == .aborted {
            record.status = .failed
            record.updatedAt = Date()
            try await runStore.save(record)
            return .failed(record, reason: "Goal is aborted in AgentRuntime")
        }

        // 3. Scan for attempts in STARTED_UNKNOWN
        let attempts = try await attemptStore.attempts(for: runID)
        let startedUnknownAttempts = attempts.filter { $0.status == .startedUnknown }

        for var attempt in startedUnknownAttempts {
            let resolution = await executionBoundary.resolveEvidence(attempt: attempt)

            switch resolution {
            case .completed(let receipt):
                attempt.status = .completed
                attempt.completedAt = Date()
                attempt.receiptRef = receipt.receiptID
                try await attemptStore.saveAttempt(attempt)
                try await attemptStore.saveReceipt(receipt)

            case .notStarted:
                attempt.status = .notStarted
                try await attemptStore.saveAttempt(attempt)

            case .unknown, .unavailable:
                // Non-idempotent or unknown truth halts fail-closed
                attempt.status = .unresolved
                try await attemptStore.saveAttempt(attempt)

                record.status = .interrupted
                record.updatedAt = Date()
                try await runStore.save(record)

                return .interrupted(
                    record,
                    reason: "Execution attempt \(attempt.attemptID.rawValue) in state \(attempt.status.rawValue) with evidence \(resolution)"
                )
            }
        }

        record.status = .running
        record.updatedAt = Date()
        try await runStore.save(record)

        return .resumed(record)
    }

    public func recoverStateJournal(runID: RunID, traceID: TraceID) async throws {
        let entries = try await journalStore.entries(for: runID)
        let pending = entries.filter { $0.status != .finalized && $0.status != .aborted }

        for var entry in pending {
            switch entry.status {
            case .prepared:
                // State was not committed; abort journal entry
                entry.status = .aborted
                entry.updatedAt = Date()
                try await journalStore.saveEntry(entry)

            case .stateCommitted, .auditCommitted:
                // Replay audit log append with STABLE EventID
                let auditEvent = ExecutionEvent(
                    id: entry.eventID,
                    traceID: traceID,
                    kind: .stateUpdated,
                    timestamp: Date(),
                    payload: [
                        "goalID": entry.goalID.rawValue,
                        "targetStatus": entry.targetStatus.rawValue,
                        "replayed": "true",
                    ]
                )
                try await eventLog.append(auditEvent)

                entry.status = .finalized
                entry.updatedAt = Date()
                try await journalStore.saveEntry(entry)

            case .finalized, .aborted:
                break
            }
        }
    }
}
