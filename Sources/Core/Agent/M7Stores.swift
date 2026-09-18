import Foundation
import PAFoundation

public protocol RunStore: Sendable {
    func save(_ record: RunRecord) async throws
    func record(for runID: RunID) async throws -> RunRecord?
    func records(for goalID: GoalID) async throws -> [RunRecord]
    func allRecords() async throws -> [RunRecord]
}

public actor InMemoryRunStore: RunStore {
    private var recordsByRunID: [RunID: RunRecord] = [:]

    public init() {}

    public func save(_ record: RunRecord) async throws {
        recordsByRunID[record.runID] = record
    }

    public func record(for runID: RunID) async throws -> RunRecord? {
        recordsByRunID[runID]
    }

    public func records(for goalID: GoalID) async throws -> [RunRecord] {
        recordsByRunID.values.filter { $0.goalID == goalID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func allRecords() async throws -> [RunRecord] {
        recordsByRunID.values.sorted { $0.createdAt < $1.createdAt }
    }
}

public protocol ExecutionAttemptStore: Sendable {
    func saveAttempt(_ attempt: ExecutionAttempt) async throws
    func attempt(for attemptID: ExecutionAttemptID) async throws -> ExecutionAttempt?
    func attempts(for runID: RunID) async throws -> [ExecutionAttempt]
    func attempt(forIdempotencyKey key: String) async throws -> ExecutionAttempt?
    func saveReceipt(_ receipt: ExecutionReceipt) async throws
    func receipt(for receiptID: String) async throws -> ExecutionReceipt?
    func receipt(forAttemptID attemptID: ExecutionAttemptID) async throws -> ExecutionReceipt?
    func receipt(forIdempotencyKey key: String) async throws -> ExecutionReceipt?
}

public actor InMemoryExecutionAttemptStore: ExecutionAttemptStore {
    private var attemptsByID: [ExecutionAttemptID: ExecutionAttempt] = [:]
    private var attemptsByIdempotencyKey: [String: ExecutionAttempt] = [:]
    private var receiptsByID: [String: ExecutionReceipt] = [:]
    private var receiptsByAttemptID: [ExecutionAttemptID: ExecutionReceipt] = [:]
    private var receiptsByIdempotencyKey: [String: ExecutionReceipt] = [:]

    public init() {}

    public func saveAttempt(_ attempt: ExecutionAttempt) async throws {
        attemptsByID[attempt.attemptID] = attempt
        attemptsByIdempotencyKey[attempt.idempotencyKey] = attempt
    }

    public func attempt(for attemptID: ExecutionAttemptID) async throws -> ExecutionAttempt? {
        attemptsByID[attemptID]
    }

    public func attempts(for runID: RunID) async throws -> [ExecutionAttempt] {
        attemptsByID.values.filter { $0.runID == runID }.sorted {
            ($0.startedAt ?? Date.distantPast) < ($1.startedAt ?? Date.distantPast)
        }
    }

    public func attempt(forIdempotencyKey key: String) async throws -> ExecutionAttempt? {
        attemptsByIdempotencyKey[key]
    }

    public func saveReceipt(_ receipt: ExecutionReceipt) async throws {
        receiptsByID[receipt.receiptID] = receipt
        receiptsByAttemptID[receipt.attemptID] = receipt
        receiptsByIdempotencyKey[receipt.idempotencyKey] = receipt
    }

    public func receipt(for receiptID: String) async throws -> ExecutionReceipt? {
        receiptsByID[receiptID]
    }

    public func receipt(forAttemptID attemptID: ExecutionAttemptID) async throws -> ExecutionReceipt? {
        receiptsByAttemptID[attemptID]
    }

    public func receipt(forIdempotencyKey key: String) async throws -> ExecutionReceipt? {
        receiptsByIdempotencyKey[key]
    }
}

public protocol RunCheckpointStore: Sendable {
    func saveCheckpoint(_ checkpoint: RunCheckpoint) async throws
    func latestCheckpoint(for runID: RunID) async throws -> RunCheckpoint?
    func checkpoints(for runID: RunID) async throws -> [RunCheckpoint]
}

public actor InMemoryRunCheckpointStore: RunCheckpointStore {
    private var checkpointsByRunID: [RunID: [RunCheckpoint]] = [:]

    public init() {}

    public func saveCheckpoint(_ checkpoint: RunCheckpoint) async throws {
        var existing = checkpointsByRunID[checkpoint.runID] ?? []
        existing.append(checkpoint)
        checkpointsByRunID[checkpoint.runID] = existing
    }

    public func latestCheckpoint(for runID: RunID) async throws -> RunCheckpoint? {
        checkpointsByRunID[runID]?.max { $0.cycleIndex < $1.cycleIndex }
    }

    public func checkpoints(for runID: RunID) async throws -> [RunCheckpoint] {
        checkpointsByRunID[runID]?.sorted { $0.cycleIndex < $1.cycleIndex } ?? []
    }
}

public protocol StateJournalStore: Sendable {
    func saveEntry(_ entry: StateJournalEntry) async throws
    func entry(for journalID: UUID) async throws -> StateJournalEntry?
    func entries(for runID: RunID) async throws -> [StateJournalEntry]
    func pendingEntries() async throws -> [StateJournalEntry]
}

public actor InMemoryStateJournalStore: StateJournalStore {
    private var entriesByID: [UUID: StateJournalEntry] = [:]

    public init() {}

    public func saveEntry(_ entry: StateJournalEntry) async throws {
        entriesByID[entry.journalID] = entry
    }

    public func entry(for journalID: UUID) async throws -> StateJournalEntry? {
        entriesByID[journalID]
    }

    public func entries(for runID: RunID) async throws -> [StateJournalEntry] {
        entriesByID.values.filter { $0.runID == runID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func pendingEntries() async throws -> [StateJournalEntry] {
        entriesByID.values.filter { $0.status != .finalized && $0.status != .aborted }.sorted { $0.createdAt < $1.createdAt }
    }
}
