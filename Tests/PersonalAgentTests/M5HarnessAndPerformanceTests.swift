import Testing
import Foundation
import PAFoundation
import PAStorage
import PAMemory
import PAArchitecture

/// Configuration options for fault injection in simulated cloud stores.
public enum CloudFaultPolicy: Sendable, Equatable {
    case none
    case alwaysThrow(CloudStorageError)
    case failEveryNthCall(n: Int, error: CloudStorageError)
    case failSpecificID(id: String, error: CloudStorageError)
    case transientFailureThenSuccess(failCount: Int, error: CloudStorageError)
    case rateLimited
    case unauthorized
}

/// Actor-isolated cloud store implementation with rich fault injection capabilities.
public actor FaultInjectingCloudStore<Record: StorageRecord>: CloudStore {
    public let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]
    private var policy: CloudFaultPolicy = .none
    private var pushAttempts: Int = 0
    private var pullAttempts: Int = 0
    private var failureCount: Int = 0
    private var idSpecificAttempts: [String: Int] = [:]

    public init(provider: any CloudStorageProvider, policy: CloudFaultPolicy = .none) {
        self.provider = provider
        self.policy = policy
    }

    public func setFaultPolicy(_ newPolicy: CloudFaultPolicy) {
        self.policy = newPolicy
    }

    public func push(_ record: Record) async throws {
        pushAttempts += 1
        try await applyFaultPolicy(for: record.id)
        records[record.id] = record
    }

    public func pull(id: String) async throws -> Record? {
        pullAttempts += 1
        try await applyFaultPolicy(for: id)
        return records[id]
    }

    public func setRecordDirectly(_ record: Record) {
        records[record.id] = record
    }

    public func getRecordDirectly(id: String) -> Record? {
        records[id]
    }

    public func stats() -> (pushCount: Int, pullCount: Int, failCount: Int) {
        (pushAttempts, pullAttempts, failureCount)
    }

    public func resetStats() {
        pushAttempts = 0
        pullAttempts = 0
        failureCount = 0
        idSpecificAttempts.removeAll()
    }

    private func applyFaultPolicy(for id: String) async throws {
        guard await provider.isAvailable else {
            failureCount += 1
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is unavailable")
        }

        let currentCallIndex = pushAttempts + pullAttempts

        switch policy {
        case .none:
            break

        case .alwaysThrow(let error):
            failureCount += 1
            throw error

        case .failEveryNthCall(let n, let error):
            if n > 0 && currentCallIndex % n == 0 {
                failureCount += 1
                throw error
            }

        case .failSpecificID(let targetID, let error):
            if id == targetID {
                failureCount += 1
                throw error
            }

        case .transientFailureThenSuccess(let failCount, let error):
            let countForID = (idSpecificAttempts[id] ?? 0) + 1
            idSpecificAttempts[id] = countForID
            if countForID <= failCount {
                failureCount += 1
                throw error
            }

        case .rateLimited:
            failureCount += 1
            throw CloudStorageError.storeFailed("429 Too Many Requests: Rate limit exceeded")

        case .unauthorized:
            failureCount += 1
            throw CloudStorageError.unauthorized("401 Unauthorized: Invalid API token")
        }
    }
}

/// Actor-isolated cloud store simulating network latency via deterministic yield loops.
public actor SimulatedLatencyCloudStore<Record: StorageRecord>: CloudStore {
    public let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]
    private let yieldsPerOperation: Int
    private var activeRequests: Int = 0
    private var completedRequests: Int = 0
    private var pushCount: Int = 0
    private var pullCount: Int = 0

    public init(provider: any CloudStorageProvider, yieldsPerOperation: Int = 5) {
        self.provider = provider
        self.yieldsPerOperation = yieldsPerOperation
    }

    public func push(_ record: Record) async throws {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider offline")
        }
        activeRequests += 1
        pushCount += 1
        defer {
            activeRequests -= 1
            completedRequests += 1
        }

        for _ in 0..<yieldsPerOperation {
            await Task.yield()
        }

        records[record.id] = record
    }

    public func pull(id: String) async throws -> Record? {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider offline")
        }
        activeRequests += 1
        pullCount += 1
        defer {
            activeRequests -= 1
            completedRequests += 1
        }

        for _ in 0..<yieldsPerOperation {
            await Task.yield()
        }

        return records[id]
    }

    public func requestMetrics() -> (active: Int, completed: Int, pushes: Int, pulls: Int) {
        (activeRequests, completedRequests, pushCount, pullCount)
    }
}

// Helper resolver for M5.5 conflict performance tests
private func defaultM55ConflictResolver(
    local: MemoryStorageRecord,
    remote: MemoryStorageRecord,
    policy: ConflictResolution
) throws -> MemoryStorageRecord {
    let content: String
    switch policy {
    case .keepLocal:
        content = local.record.content
    case .keepRemote:
        content = remote.record.content
    case .merge:
        content = "\(local.record.content)\n\(remote.record.content)"
    case .requireUser:
        throw CloudStorageError.storeFailed("requireUser must be handled prior to resolution")
    }

    let mergedRecord = MemoryRecord(
        id: local.record.id,
        kind: local.record.kind,
        content: content,
        provenance: local.record.provenance,
        createdAt: local.record.createdAt,
        updatedAt: Date(),
        scope: local.record.scope,
        lifecycle: local.record.lifecycle,
        importance: max(local.record.importance, remote.record.importance),
        metadata: local.record.metadata,
        version: local.version,
        parentVersion: local.parentVersion,
        revisionToken: local.revisionToken,
        parentRevisionToken: local.parentRevisionToken,
        ancestorRevisionTokens: local.ancestorRevisionTokens.union(remote.ancestorRevisionTokens)
    )
    return MemoryStorageRecord(mergedRecord)
}

private actor TestGate {
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var hasReleased = false

    func notifyEntered() {
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func awaitRelease() async {
        if hasReleased { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        hasReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// Actor-isolated cloud store with explicit barrier instrumentation for deterministic concurrency testing.
private actor InstrumentedCloudStore<Record: StorageRecord>: CloudStore {
    let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]
    let gate: TestGate
    let triggerID: String

    init(provider: any CloudStorageProvider, gate: TestGate, triggerID: String) {
        self.provider = provider
        self.gate = gate
        self.triggerID = triggerID
    }

    func push(_ record: Record) async throws {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is unavailable")
        }
        if record.id == triggerID {
            await gate.notifyEntered()
            await gate.awaitRelease()
        }
        records[record.id] = record
    }

    func pull(id: String) async throws -> Record? {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is unavailable")
        }
        if id == triggerID {
            await gate.notifyEntered()
            await gate.awaitRelease()
        }
        return records[id]
    }
}

@Suite("M5.5 Performance & Integration Gate Harness Tests")
struct M5HarnessAndPerformanceTests {

    // 1. Concurrent Sync Operations
    @Test func testConcurrentSyncOperationAndEnqueueing() async throws {
        let gate = TestGate()
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "concurrent-cloud", isAvailable: true)
        let triggerID = "conc-rec-0"
        let cloudStore = InstrumentedCloudStore<MemoryStorageRecord>(provider: provider, gate: gate, triggerID: triggerID)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let totalItems = 50

        // Seed initial records #0..#49
        for i in 0..<totalItems {
            let itemID = "conc-rec-\(i)"
            let rec = MemoryRecord(
                id: MemoryRecordID(rawValue: itemID),
                kind: .fact,
                content: "Concurrent content \(itemID)",
                provenance: Provenance(source: "user"),
                version: 1
            )
            let storageRec = MemoryStorageRecord(rec)
            try await localStore.upsert(storageRec)
            try await engine.enqueueLocalChange(id: itemID)
        }

        #expect(await queue.count() == totalItems)

        // Seed record #51 (lateID) in localStore only (not yet enqueued)
        let lateID = "late-rec-999"
        let lateRec = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: lateID),
                kind: .fact,
                content: "Late arriving record",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(lateRec)

        // 1. Start synchronize()
        let syncTask = Task {
            try await engine.synchronize()
        }

        // 2 & 3. Confirm via explicit signal that trigger record cloud operation has been entered
        await gate.waitUntilEntered()

        // 4. Enqueue record #51 while first sync is suspended in trigger record cloud operation
        try await engine.enqueueLocalChange(id: lateID)

        // 5. Release barrier
        await gate.release()

        // 6. Await first synchronization and confirm #51 was not drained in pass 1
        try await syncTask.value
        #expect(await queue.contains(id: lateID))

        // 7. Run second synchronization
        try await engine.synchronize()

        // 8. Verify #51 is drained and final invariants hold
        #expect(await queue.count() == 0)

        // Verify cloud store holds all records including lateID
        for i in 0..<totalItems {
            let pulled = try await cloudStore.pull(id: "conc-rec-\(i)")
            #expect(pulled != nil)
            #expect(pulled?.id == "conc-rec-\(i)")
        }
        let latePulled = try await cloudStore.pull(id: lateID)
        #expect(latePulled != nil)
        #expect(latePulled?.id == lateID)
    }

    // 2. High-Latency Cloud Simulation
    @Test func testSimulatedHighLatencyCloudBehavior() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "high-latency-cloud", isAvailable: true)
        let cloudStore = SimulatedLatencyCloudStore<MemoryStorageRecord>(provider: provider, yieldsPerOperation: 5)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        for i in 0..<10 {
            let id = "latency-rec-\(i)"
            let rec = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: id),
                    kind: .fact,
                    content: "Latency test record \(i)",
                    provenance: Provenance(source: "user"),
                    version: 1
                )
            )
            try await localStore.upsert(rec)
            try await engine.enqueueLocalChange(id: id)
        }

        #expect(await queue.count() == 10)

        try await engine.synchronize()

        #expect(await queue.count() == 0)
        for i in 0..<10 {
            let pulled = try await cloudStore.pull(id: "latency-rec-\(i)")
            #expect(pulled != nil)
        }
    }

    // 3. Fault Injection - Transient Failures & Recovery
    @Test func testFaultInjectionTransientFailuresAndRecovery() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "faulty-cloud", isAvailable: true)
        let faultyCloud = FaultInjectingCloudStore<MemoryStorageRecord>(
            provider: provider,
            policy: .transientFailureThenSuccess(failCount: 2, error: CloudStorageError.storeFailed("Transient cloud push failure"))
        )
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: faultyCloud, queue: queue)

        let id = "fault-rec-1"
        let localRec = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: id),
                kind: .fact,
                content: "Fault injection test content",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )
        try await localStore.upsert(localRec)
        try await engine.enqueueLocalChange(id: id)

        // Attempt 1: Expect failure due to transient fault
        do {
            try await engine.synchronize()
            Issue.record("Expected first sync to fail under fault injection")
        } catch let err as CloudStorageError {
            if case .storeFailed = err {
                // Expected transient fault
            } else {
                Issue.record("Expected storeFailed, got \(err)")
            }
        }

        // Verify local state and queue preserved after failure
        #expect(try await localStore.fetch(id: id) != nil)
        #expect(await queue.count() == 1)

        // Attempt 2: Expect failure (failCount = 2)
        do {
            try await engine.synchronize()
            Issue.record("Expected second sync to fail under fault injection")
        } catch {}

        // Attempt 3: Expect success after transient failures exhausted
        try await engine.synchronize()

        #expect(await queue.count() == 0)
        let synced = try await faultyCloud.pull(id: id)
        #expect(synced?.id == id)
    }

    // 4. Fault Injection - Rate Limited & Unauthorized Errors
    @Test func testFaultInjectionRateLimitingAndUnauthorizedHandling() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "auth-cloud", isAvailable: true)
        let faultyCloud = FaultInjectingCloudStore<MemoryStorageRecord>(
            provider: provider,
            policy: .unauthorized
        )
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: faultyCloud, queue: queue)

        let id = "auth-rec-1"
        try await localStore.upsert(
            MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: id),
                    kind: .fact,
                    content: "Secret content",
                    provenance: Provenance(source: "user"),
                    version: 1
                )
            )
        )
        try await engine.enqueueLocalChange(id: id)

        do {
            try await engine.synchronize()
            Issue.record("Expected unauthorized error")
        } catch let err as CloudStorageError {
            #expect(err == .unauthorized("401 Unauthorized: Invalid API token"))
        }

        // Local state preserved
        #expect(await queue.contains(id: id))
        #expect(try await localStore.fetch(id: id) != nil)

        // Switch fault policy to rateLimited
        await faultyCloud.setFaultPolicy(.rateLimited)

        do {
            try await engine.synchronize()
            Issue.record("Expected rate limited error")
        } catch let err as CloudStorageError {
            if case .storeFailed(let msg) = err {
                #expect(msg.contains("429"))
            } else {
                Issue.record("Expected storeFailed 429, got \(err)")
            }
        }

        #expect(await queue.contains(id: id))
    }

    // 5. Large Dataset Sync Scale Test (1,000+ Items)
    @Test func testLargeDatasetSyncPerformance() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "scale-cloud", isAvailable: true)
        let cloudStore = InMemoryCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue()
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let recordCount = 1000

        for i in 0..<recordCount {
            let id = "large-rec-\(i)"
            let rec = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: id),
                    kind: .fact,
                    content: "Large dataset payload \(i) with structured metadata and history tracking.",
                    provenance: Provenance(source: "bench"),
                    version: 1
                )
            )
            try await localStore.upsert(rec)
            try await engine.enqueueLocalChange(id: id)
        }

        #expect(await queue.count() == recordCount)

        let startTime = Date()
        try await engine.synchronize()
        let duration = Date().timeIntervalSince(startTime)

        #expect(await queue.count() == 0)

        // Verify processing completed efficiently (bounded time check, generous threshold)
        #expect(duration < 10.0, "Batch sync of 1000 records should complete well under 10 seconds (took \(duration)s)")

        // Verify random sample of synced records
        for sample in [0, 250, 500, 750, 999] {
            let pulled = try await cloudStore.pull(id: "large-rec-\(sample)")
            #expect(pulled?.id == "large-rec-\(sample)")
        }
    }

    // 6. Large Dataset Conflict Resolution Performance
    @Test func testLargeDatasetConflictResolutionPerformance() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "conflict-cloud", isAvailable: true)
        let cloudStore = FaultInjectingCloudStore<MemoryStorageRecord>(provider: provider, policy: .none)
        let queue = PASyncQueue()
        let verifier = DefaultLineageVerifier(historyStore: localStore)
        let engine = PASyncEngine(
            localStore: localStore,
            cloudStore: cloudStore,
            queue: queue,
            conflictResolver: defaultM55ConflictResolver,
            lineageVerifier: verifier
        )

        let conflictCount = 200

        for i in 0..<conflictCount {
            let id = "conflict-rec-\(i)"

            let localV1 = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: id),
                    kind: .fact,
                    content: "Local version content \(i)",
                    provenance: Provenance(source: "user"),
                    version: 1,
                    revisionToken: "\(id)-loc-v1"
                )
            )

            let remoteV1Divergent = MemoryStorageRecord(
                MemoryRecord(
                    id: MemoryRecordID(rawValue: id),
                    kind: .fact,
                    content: "Remote version content \(i)",
                    provenance: Provenance(source: "agent"),
                    version: 1,
                    revisionToken: "\(id)-rem-v1"
                )
            )

            try await localStore.upsert(localV1)
            await cloudStore.setRecordDirectly(remoteV1Divergent)
            try await engine.enqueueLocalChange(id: id)
        }

        // Synchronize detects conflicts for all 200 items
        try await engine.synchronize()

        let pending = await engine.pendingConflicts()
        #expect(pending.count == conflictCount)

        // Resolve all conflicts concurrently using keepLocal policy
        await withTaskGroup(of: Void.self) { group in
            for c in pending {
                group.addTask {
                    try? await engine.resolve(c, policy: .keepLocal)
                }
            }
        }

        #expect(await engine.pendingConflicts().isEmpty)
        #expect(await queue.count() == 0)

        // Verify resolved versions in cloud and local stores
        for i in [0, 50, 100, 150, 199] {
            let id = "conflict-rec-\(i)"
            let localResolved = try await localStore.fetch(id: id)
            let cloudResolved = try await cloudStore.pull(id: id)

            #expect(localResolved?.version == 2)
            #expect(cloudResolved?.version == 2)
            #expect(localResolved?.record.content == "Local version content \(i)")
            #expect(cloudResolved?.record.content == "Local version content \(i)")
        }
    }

    // 7. Post-M5.4 Integrated Recovery & Queue Status Invariants
    @Test func testIntegratedM54RecoveryEngineInvariants() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "offline-cloud", isAvailable: false)
        let cloudStore = InMemoryCloudStore<MemoryStorageRecord>(provider: provider)
        let queue = PASyncQueue(maxRetries: 3)
        let engine = PASyncEngine(localStore: localStore, cloudStore: cloudStore, queue: queue)

        let id = "m54-recovery-rec-1"
        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: id),
                kind: .fact,
                content: "Offline queued item awaiting recovery",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )

        try await localStore.upsert(record)
        try await engine.enqueueLocalChange(id: id)

        // When offline, synchronize throws CloudStorageError.unavailable
        do {
            try await engine.synchronize()
            Issue.record("Expected unavailable error when cloud provider is offline")
        } catch let err as CloudStorageError {
            if case .unavailable = err {
                // Expected offline boundary behavior
            } else {
                Issue.record("Expected unavailable, got \(err)")
            }
        }

        // Verify queued work remains intact and status reflects pending retry metadata
        #expect(await queue.count() == 1)
        #expect(await queue.contains(id: id))
        #expect(await queue.status(for: id) == .pending)
    }
}
