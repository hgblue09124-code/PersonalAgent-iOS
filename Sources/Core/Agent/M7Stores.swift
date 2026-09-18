import Foundation
import PAFoundation
import PAEvents

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

public actor FileBackedRunStore: RunStore {
    private let fileURL: URL
    private var recordsByRunID: [RunID: RunRecord] = [:]

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.fileURL = directoryURL.appendingPathComponent("run_records.json")

        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([RunRecord].self, from: data)
            for r in records {
                recordsByRunID[r.runID] = r
            }
        }
    }

    public func save(_ record: RunRecord) async throws {
        recordsByRunID[record.runID] = record
        try persist()
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

    private func persist() throws {
        let array = Array(recordsByRunID.values)
        let data = try JSONEncoder().encode(array)
        try data.write(to: fileURL, options: .atomic)
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

public actor FileBackedExecutionAttemptStore: ExecutionAttemptStore {
    private let attemptsFileURL: URL
    private let receiptsFileURL: URL
    private var attemptsByID: [ExecutionAttemptID: ExecutionAttempt] = [:]
    private var attemptsByIdempotencyKey: [String: ExecutionAttempt] = [:]
    private var receiptsByID: [String: ExecutionReceipt] = [:]
    private var receiptsByAttemptID: [ExecutionAttemptID: ExecutionReceipt] = [:]
    private var receiptsByIdempotencyKey: [String: ExecutionReceipt] = [:]

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.attemptsFileURL = directoryURL.appendingPathComponent("execution_attempts.json")
        self.receiptsFileURL = directoryURL.appendingPathComponent("execution_receipts.json")

        if fm.fileExists(atPath: attemptsFileURL.path) {
            let data = try Data(contentsOf: attemptsFileURL)
            let attempts = try JSONDecoder().decode([ExecutionAttempt].self, from: data)
            for a in attempts {
                attemptsByID[a.attemptID] = a
                attemptsByIdempotencyKey[a.idempotencyKey] = a
            }
        }

        if fm.fileExists(atPath: receiptsFileURL.path) {
            let data = try Data(contentsOf: receiptsFileURL)
            let receipts = try JSONDecoder().decode([ExecutionReceipt].self, from: data)
            for r in receipts {
                receiptsByID[r.receiptID] = r
                receiptsByAttemptID[r.attemptID] = r
                receiptsByIdempotencyKey[r.idempotencyKey] = r
            }
        }
    }

    public func saveAttempt(_ attempt: ExecutionAttempt) async throws {
        attemptsByID[attempt.attemptID] = attempt
        attemptsByIdempotencyKey[attempt.idempotencyKey] = attempt
        try persistAttempts()
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
        try persistReceipts()
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

    private func persistAttempts() throws {
        let array = Array(attemptsByID.values)
        let data = try JSONEncoder().encode(array)
        try data.write(to: attemptsFileURL, options: .atomic)
    }

    private func persistReceipts() throws {
        let array = Array(receiptsByID.values)
        let data = try JSONEncoder().encode(array)
        try data.write(to: receiptsFileURL, options: .atomic)
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

public actor FileBackedRunCheckpointStore: RunCheckpointStore {
    private let fileURL: URL
    private var checkpointsByRunID: [RunID: [RunCheckpoint]] = [:]

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.fileURL = directoryURL.appendingPathComponent("run_checkpoints.json")

        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let list = try JSONDecoder().decode([RunCheckpoint].self, from: data)
            for c in list {
                var existing = checkpointsByRunID[c.runID] ?? []
                existing.append(c)
                checkpointsByRunID[c.runID] = existing
            }
        }
    }

    public func saveCheckpoint(_ checkpoint: RunCheckpoint) async throws {
        var existing = checkpointsByRunID[checkpoint.runID] ?? []
        existing.append(checkpoint)
        checkpointsByRunID[checkpoint.runID] = existing
        try persist()
    }

    public func latestCheckpoint(for runID: RunID) async throws -> RunCheckpoint? {
        checkpointsByRunID[runID]?.max { $0.cycleIndex < $1.cycleIndex }
    }

    public func checkpoints(for runID: RunID) async throws -> [RunCheckpoint] {
        checkpointsByRunID[runID]?.sorted { $0.cycleIndex < $1.cycleIndex } ?? []
    }

    private func persist() throws {
        let all = checkpointsByRunID.values.flatMap { $0 }
        let data = try JSONEncoder().encode(all)
        try data.write(to: fileURL, options: .atomic)
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

public actor FileBackedStateJournalStore: StateJournalStore {
    private let fileURL: URL
    private var entriesByID: [UUID: StateJournalEntry] = [:]

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.fileURL = directoryURL.appendingPathComponent("state_journal.json")

        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([StateJournalEntry].self, from: data)
            for e in entries {
                entriesByID[e.journalID] = e
            }
        }
    }

    public func saveEntry(_ entry: StateJournalEntry) async throws {
        entriesByID[entry.journalID] = entry
        try persist()
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

    private func persist() throws {
        let array = Array(entriesByID.values)
        let data = try JSONEncoder().encode(array)
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor FileBackedEventLog: EventLog {
    private let fileURL: URL
    private var stored: [ExecutionEvent] = []

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.fileURL = directoryURL.appendingPathComponent("execution_events.json")

        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.stored = try JSONDecoder().decode([ExecutionEvent].self, from: data)
        }
    }

    public func append(_ event: ExecutionEvent) async throws {
        stored.append(event)
        try persist()
    }

    public func events(for traceID: TraceID) async throws -> [ExecutionEvent] {
        stored.filter { $0.traceID == traceID }
    }

    public func allEvents() async throws -> [ExecutionEvent] {
        stored
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(stored)
        try data.write(to: fileURL, options: .atomic)
    }
}

public protocol MutationEvidenceStore: Sendable {
    func recordMutation(token: UUID) async throws
    func hasAppliedMutation(token: UUID) async -> Bool
    func allTokens() async throws -> Set<UUID>
}

public actor InMemoryMutationEvidenceStore: MutationEvidenceStore {
    private var tokens: Set<UUID> = []

    public init() {}

    public func recordMutation(token: UUID) async throws {
        tokens.insert(token)
    }

    public func hasAppliedMutation(token: UUID) async -> Bool {
        tokens.contains(token)
    }

    public func allTokens() async throws -> Set<UUID> {
        tokens
    }
}

public actor FileBackedMutationStore: MutationEvidenceStore {
    private let fileURL: URL
    private var tokens: Set<UUID> = []

    public init(directoryURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        self.fileURL = directoryURL.appendingPathComponent("mutation_evidence.json")

        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let array = try JSONDecoder().decode([UUID].self, from: data)
            self.tokens = Set(array)
        }
    }

    public func recordMutation(token: UUID) async throws {
        tokens.insert(token)
        try persist()
    }

    public func hasAppliedMutation(token: UUID) async -> Bool {
        tokens.contains(token)
    }

    public func allTokens() async throws -> Set<UUID> {
        tokens
    }

    private func persist() throws {
        let array = Array(tokens)
        let data = try JSONEncoder().encode(array)
        try data.write(to: fileURL, options: .atomic)
    }
}
