import Foundation
import PAFoundation
import PAKernel
import PAObservability
import PAEvents
import PAPolicy
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

        // 2. Reconcile with AgentRuntime GoalStatus (sole AgentState authority)
        guard let goal = await runtime.goal(id: record.goalID) else {
            record.status = .failed
            record.updatedAt = Date()
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

        // 3. Scan for attempts in STARTED_UNKNOWN and resolve capability-aware
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
                // Check capability for attempt target
                if let toolID = attempt.toolID, let cap = await executionBoundary.targetCapability(for: toolID) {
                    if cap.idempotencyClass == .idempotent {
                        // Idempotent target: mark as NOT_STARTED so retry is allowed with same idempotencyKey
                        attempt.status = .notStarted
                        try await attemptStore.saveAttempt(attempt)
                        continue
                    }
                }

                // Non-idempotent target or unknown capability: halt fail closed as UNRESOLVED / INTERRUPTED
                attempt.status = .unresolved
                try await attemptStore.saveAttempt(attempt)

                record.status = .interrupted
                record.updatedAt = Date()
                try await runStore.save(record)

                return .interrupted(
                    record,
                    reason: "Execution attempt \(attempt.attemptID.rawValue) for non-idempotent target in state STARTED_UNKNOWN with evidence \(resolution)"
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
                // Check explicit authoritative mutation token on AgentRuntime
                let applied = await runtime.hasAppliedMutation(token: entry.journalID)
                if applied {
                    // State update was already applied to AgentRuntime prior to crash
                    entry.status = .stateCommitted
                    entry.updatedAt = Date()
                    try await journalStore.saveEntry(entry)

                    let payload = IdempotentEventLog.parseCanonicalPayload(entry.canonicalEventPayload)
                    let auditEvent = ExecutionEvent(
                        id: entry.eventID,
                        traceID: traceID,
                        kind: .stateUpdated,
                        timestamp: Date(),
                        payload: payload
                    )
                    try await eventLog.append(auditEvent)

                    entry.status = .auditCommitted
                    entry.updatedAt = Date()
                    try await journalStore.saveEntry(entry)

                    entry.status = .finalized
                    entry.updatedAt = Date()
                    try await journalStore.saveEntry(entry)
                } else {
                    // State update was not applied; abort journal entry
                    entry.status = .aborted
                    entry.updatedAt = Date()
                    try await journalStore.saveEntry(entry)
                }

            case .stateCommitted:
                let payload = IdempotentEventLog.parseCanonicalPayload(entry.canonicalEventPayload)
                let auditEvent = ExecutionEvent(
                    id: entry.eventID,
                    traceID: traceID,
                    kind: .stateUpdated,
                    timestamp: Date(),
                    payload: payload
                )
                try await eventLog.append(auditEvent)

                entry.status = .auditCommitted
                entry.updatedAt = Date()
                try await journalStore.saveEntry(entry)

                entry.status = .finalized
                entry.updatedAt = Date()
                try await journalStore.saveEntry(entry)

            case .auditCommitted:
                entry.status = .finalized
                entry.updatedAt = Date()
                try await journalStore.saveEntry(entry)

            case .finalized, .aborted:
                break
            }
        }
    }

    public static func parseCanonicalPayload(_ canonicalString: String) -> [String: String] {
        var dict: [String: String] = [:]
        let pairs = canonicalString.split(separator: "&")
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                dict[String(kv[0])] = String(kv[1])
            } else if kv.count == 1 {
                dict[String(kv[0])] = ""
            }
        }
        return dict
    }
}
