import Testing
import Foundation
import PAFoundation
import PAKernel
import PAEvents
import PAPolicy
import PAAgency
import PACognition
import PAModules
import PATools
import PAComposition

@Suite("M7 Failure-Window Matrix & Regression Tests")
struct M7FailureWindowMatrixTests {

    // 1. executor completed, verification completed -> success
    @Test("Failure Window 1: executor completed + verification completed -> success")
    func testExecutorCompletedVerificationCompleted() async throws {
        struct CompletedResolver: ExecutionEvidenceResolver {
            let receipt: ExecutionReceipt
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .completed(receipt)
            }
        }
        let tool = EchoTool()
        let receipt = ExecutionReceipt(
            receiptID: "r-verified-1",
            attemptID: ExecutionAttemptID(),
            toolID: tool.manifest.id,
            idempotencyKey: "key-verified-1",
            outputSummary: "Success"
        )
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: CompletedResolver(receipt: receipt),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Verified execution test")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "hello",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(obs.succeeded)
        #expect(attempt.status == .completed)
    }

    // 2. executor completed, verification failed -> no success
    @Test("Failure Window 2: executor completed + verification failed -> no success")
    func testExecutorCompletedVerificationFailed() async throws {
        struct FailingResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .unknown
            }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .nonIdempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: FailingResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Failed verification test")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "hello",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .unresolved)
    }

    // 3. executor completed, verification unknown -> no success
    @Test("Failure Window 3: executor completed + verification unknown -> no success")
    func testExecutorCompletedVerificationUnknown() async throws {
        struct UnknownResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .unknown
            }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: UnknownResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Unknown verification test")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "hello",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)
    }

    // 4. executor completed, verification unavailable -> no success
    @Test("Failure Window 4: executor completed + verification unavailable -> no success")
    func testExecutorCompletedVerificationUnavailable() async throws {
        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .nonIdempotent, supportsEvidenceResolution: false)
        let composition = try await M7CompositionRoot(targetCapabilities: [cap], tools: [tool])

        let goal = Goal(statement: "Unavailable verification test")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "hello",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .unresolved)
    }

    // 5 & 6. executor throws / timeout -> STARTED_UNKNOWN
    @Test("Failure Windows 5 & 6: executor throws / times out -> STARTED_UNKNOWN, never FAILED")
    func testExecutorThrowLeavesStatusStartedUnknown() async throws {
        struct ThrowingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "throwingTool"),
                name: "Throwing",
                version: SemanticVersion(major: 0, minor: 1, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.throw.in"),
                outputSchema: SchemaDocument(identifier: "tool.throw.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct TargetError: Error {}
                throw TargetError()
            }
        }

        let tool = ThrowingTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: false)
        let composition = try await M7CompositionRoot(targetCapabilities: [cap], tools: [tool])

        let goal = Goal(statement: "Throwing test")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)
    }

    // 7. PREPARED + crash before mutation -> NOT_APPLIED
    @Test("Failure Window 7: PREPARED journal entry + crash before mutation -> NOT_APPLIED / aborted")
    func testPreparedCrashBeforeMutation() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Crash before mutation")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let eventID = EventID()
        let journalID = UUID()

        let entry = StateJournalEntry(
            journalID: journalID,
            runID: record.runID,
            goalID: goal.id,
            targetStatus: .completed,
            eventID: eventID,
            canonicalEventPayload: IdempotentEventLog.canonicalString(for: ["goalID": goal.id.rawValue, "targetStatus": "completed"]),
            status: .prepared
        )
        try await composition.journalStore.saveEntry(entry)

        try await composition.recoveryEngine.recoverStateJournal(runID: record.runID, traceID: record.traceID)

        let updated = try await composition.journalStore.entry(for: journalID)
        #expect(updated?.status == .aborted)
    }

    // 8. PREPARED + mutation happened + journal missing -> APPLIED_BUT_NOT_JOURNALED
    @Test("Failure Window 8: PREPARED journal entry + mutation happened -> APPLIED_BUT_NOT_JOURNALED / finalized")
    func testPreparedMutationHappened() async throws {
        let composition = try await M7CompositionRoot()
        let goal = Goal(statement: "Mutation happened")
        try await composition.runtime.submit(goal: goal)

        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let eventID = EventID()
        let journalID = UUID()

        let update = StateUpdate(
            goalID: goal.id,
            targetStatus: .completed,
            evidence: ["disposition": "complete", "reason": "done"],
            mutationToken: journalID
        )
        try await composition.runtime.applyStateUpdate(update)

        let entry = StateJournalEntry(
            journalID: journalID,
            runID: record.runID,
            goalID: goal.id,
            targetStatus: .completed,
            eventID: eventID,
            canonicalEventPayload: IdempotentEventLog.canonicalString(for: ["goalID": goal.id.rawValue, "targetStatus": "completed"]),
            status: .prepared
        )
        try await composition.journalStore.saveEntry(entry)

        try await composition.recoveryEngine.recoverStateJournal(runID: record.runID, traceID: record.traceID)

        let updated = try await composition.journalStore.entry(for: journalID)
        #expect(updated?.status == .finalized)
    }

    // 11 & 12. Same EventID across fresh instance
    @Test("Failure Windows 11 & 12: EventID exactly-once across fresh IdempotentEventLog instance")
    func testEventIDExactlyOnceAcrossFreshInstance() async throws {
        let durableInnerLog = InMemoryEventLog()
        let log1 = IdempotentEventLog(innerLog: durableInnerLog)

        let eventID = EventID()
        let traceID = TraceID()
        let payloadP = ["a": "1", "b": "2"]
        let payloadQ = ["a": "1", "b": "mismatch"]

        let event1 = ExecutionEvent(id: eventID, traceID: traceID, kind: .stateUpdated, payload: payloadP)
        try await log1.append(event1)

        let count1 = (try await durableInnerLog.allEvents()).count
        #expect(count1 == 1)

        // Fresh IdempotentEventLog instance wrapping same underlying durableInnerLog
        let log2 = IdempotentEventLog(innerLog: durableInnerLog)

        // Re-append same EventID + same payload P -> idempotent success
        try await log2.append(event1)
        let count2 = (try await durableInnerLog.allEvents()).count
        #expect(count2 == 1)

        // Re-append same EventID + conflicting payload Q -> fail closed
        let eventConflicting = ExecutionEvent(id: eventID, traceID: traceID, kind: .stateUpdated, payload: payloadQ)
        do {
            try await log2.append(eventConflicting)
            #expect(Bool(false), "Should have thrown conflictingPayload")
        } catch EventLogError.conflictingPayload(let id, _, _) {
            #expect(id == eventID)
        }
    }

    // 13 & 14. Target-bound evidence resolution
    @Test("Failure Windows 13 & 14: Target-bound evidence resolution")
    func testTargetBoundEvidenceResolution() async throws {
        struct GlobalResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .notStarted
            }
        }

        let toolA = ToolID(rawValue: "targetA")
        let toolB = ToolID(rawValue: "targetB")

        let capA = ExecutionTargetCapability(toolID: toolA, idempotencyClass: .nonIdempotent, supportsEvidenceResolution: false)
        let capB = ExecutionTargetCapability(toolID: toolB, idempotencyClass: .idempotent, supportsEvidenceResolution: true)

        let composition = try await M7CompositionRoot(
            evidenceResolver: GlobalResolver(),
            targetCapabilities: [capA, capB]
        )

        let attemptA = ExecutionAttempt(runID: RunID(), actionID: ActionID(), toolID: toolA, idempotencyKey: "keyA", status: .startedUnknown)
        let attemptB = ExecutionAttempt(runID: RunID(), actionID: ActionID(), toolID: toolB, idempotencyKey: "keyB", status: .startedUnknown)

        // Target A has supportsEvidenceResolution = false -> returns unavailable (global resolver NOT invoked)
        let resA = await composition.executionBoundary.resolveEvidence(attempt: attemptA)
        #expect(resA == .unavailable)

        // Target B has supportsEvidenceResolution = true -> calls global resolver and returns notStarted
        let resB = await composition.executionBoundary.resolveEvidence(attempt: attemptB)
        #expect(resB == .notStarted)
    }

    // 17. Lossless canonical payload
    @Test("Failure Window 17: Lossless canonical payload encoding and round-trip")
    func testLosslessCanonicalPayloadRoundTrip() async throws {
        let specialPayload: [String: String] = [
            "amp": "a&b",
            "eq": "a=b",
            "percent": "100%",
            "unicode": "Xin chào thế giới 🌍",
            "empty": "",
            "newline": "line1\nline2\r\nline3",
            "quotes": "\"hello 'world'\""
        ]

        let str = IdempotentEventLog.canonicalString(for: specialPayload)
        let parsed = IdempotentEventLog.parseCanonicalPayload(str)

        #expect(parsed == specialPayload)
        #expect(parsed["amp"] == "a&b")
        #expect(parsed["eq"] == "a=b")
        #expect(parsed["unicode"] == "Xin chào thế giới 🌍")
        #expect(parsed["newline"] == "line1\nline2\r\nline3")
        #expect(parsed["empty"] == "")
    }

    // Contradiction: Executor completed + Evidence notStarted -> Fail Closed as Unresolved
    @Test("Contradiction: Executor completed + evidence notStarted fails closed as unresolved")
    func testContradictionExecutorCompletedEvidenceNotStarted() async throws {
        struct EchoTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "echoTool"),
                name: "Echo",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.echo.in"),
                outputSchema: SchemaDocument(identifier: "tool.echo.out")
            )
            func run(argumentsJSON: String) async throws -> String { "hello" }
        }

        struct ContradictionResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .notStarted
            }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: ContradictionResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Contradiction test goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "hello",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .unresolved)
        #expect(obs.summary.contains("contradiction"))
    }

    // Executor threw + Evidence completed -> Proof of completion succeeds
    @Test("Executor threw + Evidence completed resolves as completed")
    func testExecutorThrewEvidenceCompletedResolvesSuccess() async throws {
        struct ThrowingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "throwingTool2"),
                name: "Throwing2",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.throw2.in"),
                outputSchema: SchemaDocument(identifier: "tool.throw2.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct TransportError: Error {}
                throw TransportError()
            }
        }

        struct CompletedResolver: ExecutionEvidenceResolver {
            let receipt: ExecutionReceipt
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .completed(receipt)
            }
        }

        let tool = ThrowingTool()
        let receipt = ExecutionReceipt(
            receiptID: "receipt-throw-comp",
            attemptID: ExecutionAttemptID(),
            toolID: tool.manifest.id,
            idempotencyKey: "key-throw-comp",
            outputSummary: "Verified execution"
        )
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: CompletedResolver(receipt: receipt),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Throw with completed evidence goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(obs.succeeded)
        #expect(attempt.status == .completed)
        #expect(obs.summary == "Verified execution")
    }

    // Missing Target Capability -> Fails Closed
    @Test("Missing target capability declaration fails closed")
    func testMissingTargetCapabilityFailsClosed() async throws {
        struct EchoTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "unregisteredCapTool"),
                name: "UnregisteredCap",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.unregistered.in"),
                outputSchema: SchemaDocument(identifier: "tool.unregistered.out")
            )
            func run(argumentsJSON: String) async throws -> String { "hello" }
        }

        let tool = EchoTool()
        let composition = try await M7CompositionRoot(targetCapabilities: [], tools: [tool])

        let goal = Goal(statement: "Missing capability goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .failed)
        #expect(obs.summary.contains("Missing target capability"))
    }

    // Expired or Revoked Lease during execution -> Throws CapabilityLeaseError
    @Test("Expired or revoked CapabilityLease throws error during execution")
    func testExpiredOrRevokedLeaseThrows() async throws {
        struct EchoTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "leaseTool"),
                name: "LeaseTool",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.lease.in"),
                outputSchema: SchemaDocument(identifier: "tool.lease.out")
            )
            func run(argumentsJSON: String) async throws -> String { "hello" }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(targetCapabilities: [cap], tools: [tool])

        let goal = Goal(statement: "Lease test goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)

        // 1. Expired lease
        let expiredLease = CapabilityLease(
            runID: record.runID,
            expiresAt: Date().addingTimeInterval(-3600)
        )
        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        do {
            _ = try await composition.executionBoundary.executeProposal(
                proposal: proposal,
                runID: record.runID,
                goalID: goal.id,
                traceID: record.traceID,
                cycleIndex: 1,
                lease: expiredLease
            )
            #expect(Bool(false), "Expected expired lease to throw CapabilityLeaseError.expired")
        } catch is CapabilityLeaseError {
            #expect(Bool(true))
        }

        // 2. Revoked lease
        let revokedLease = CapabilityLease(runID: record.runID, isRevoked: true)
        do {
            _ = try await composition.executionBoundary.executeProposal(
                proposal: proposal,
                runID: record.runID,
                goalID: goal.id,
                traceID: record.traceID,
                cycleIndex: 1,
                lease: revokedLease
            )
            #expect(Bool(false), "Expected revoked lease to throw CapabilityLeaseError.revoked")
        } catch is CapabilityLeaseError {
            #expect(Bool(true))
        }
    }

    // Executor-produced receipt alone does NOT verify execution
    @Test("Executor-produced receipt alone does NOT verify execution")
    func testExecutorProducedReceiptDoesNotVerifyExecution() async throws {
        struct EchoTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "receiptOnlyTool"),
                name: "ReceiptOnly",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.receipt.in"),
                outputSchema: SchemaDocument(identifier: "tool.receipt.out")
            )
            func run(argumentsJSON: String) async throws -> String { "hello" }
        }

        let tool = EchoTool()
        let cap = ExecutionTargetCapability(
            toolID: tool.manifest.id,
            idempotencyClass: .idempotent,
            supportsEvidenceResolution: false
        )
        let composition = try await M7CompositionRoot(
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Receipt only test goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)
        #expect(attempt.receiptRef != nil)
    }

    // Test A: Executor non-completed + NOT_STARTED -> attempt.status == .notStarted (never .failed)
    @Test("Executor non-completed + notStarted evidence resolves as notStarted, never failed")
    func testExecutorNonCompletedNotStartedEvidence() async throws {
        struct FailingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "failingToolA"),
                name: "FailingA",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.faila.in"),
                outputSchema: SchemaDocument(identifier: "tool.faila.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct FailError: Error {}
                throw FailError()
            }
        }

        struct NotStartedResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .notStarted
            }
        }

        let tool = FailingTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: NotStartedResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Test A Goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .notStarted)
        #expect(attempt.status != .failed)
    }

    // Test B: Executor non-completed + UNKNOWN (idempotent target) -> attempt.status == .startedUnknown (never .failed)
    @Test("Executor non-completed + unknown evidence (idempotent target) resolves as startedUnknown, never failed")
    func testExecutorNonCompletedUnknownEvidenceIdempotent() async throws {
        struct FailingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "failingToolB"),
                name: "FailingB",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.failb.in"),
                outputSchema: SchemaDocument(identifier: "tool.failb.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct FailError: Error {}
                throw FailError()
            }
        }

        struct UnknownResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .unknown
            }
        }

        let tool = FailingTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: UnknownResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Test B Goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)
        #expect(attempt.status != .failed)
    }

    // Test C: Executor non-completed + UNAVAILABLE (idempotent target) -> attempt.status == .startedUnknown (never .failed)
    @Test("Executor non-completed + unavailable evidence (idempotent target) resolves as startedUnknown, never failed")
    func testExecutorNonCompletedUnavailableEvidenceIdempotent() async throws {
        struct FailingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "failingToolC"),
                name: "FailingC",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.failc.in"),
                outputSchema: SchemaDocument(identifier: "tool.failc.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct FailError: Error {}
                throw FailError()
            }
        }

        struct UnavailableResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .unavailable
            }
        }

        let tool = FailingTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .idempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: UnavailableResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Test C Goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .startedUnknown)
        #expect(attempt.status != .failed)
    }

    // Test D: Executor non-completed + UNKNOWN (non-idempotent target) -> attempt.status == .unresolved (never .failed)
    @Test("Executor non-completed + unknown evidence (non-idempotent target) resolves as unresolved, never failed")
    func testExecutorNonCompletedUnknownEvidenceNonIdempotent() async throws {
        struct FailingTool: Tool {
            let manifest = ToolManifest(
                id: ToolID(rawValue: "failingToolD"),
                name: "FailingD",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                requiredCapabilities: [.read],
                inputSchema: SchemaDocument(identifier: "tool.faild.in"),
                outputSchema: SchemaDocument(identifier: "tool.faild.out")
            )
            func run(argumentsJSON: String) async throws -> String {
                struct FailError: Error {}
                throw FailError()
            }
        }

        struct UnknownResolver: ExecutionEvidenceResolver {
            func resolve(attemptID: ExecutionAttemptID, idempotencyKey: String) async throws -> EvidenceResolution {
                .unknown
            }
        }

        let tool = FailingTool()
        let cap = ExecutionTargetCapability(toolID: tool.manifest.id, idempotencyClass: .nonIdempotent, supportsEvidenceResolution: true)
        let composition = try await M7CompositionRoot(
            evidenceResolver: UnknownResolver(),
            targetCapabilities: [cap],
            tools: [tool]
        )

        let goal = Goal(statement: "Test D Goal")
        try await composition.runtime.submit(goal: goal)
        let record = try await composition.lifecycleManager.createRun(goalID: goal.id)
        let lease = CapabilityLease(runID: record.runID)

        let proposal = ActionProposal(
            actionID: ActionID(),
            planID: PlanID(),
            toolID: tool.manifest.id,
            description: "test",
            capabilities: [.read]
        )

        let (obs, attempt) = try await composition.executionBoundary.executeProposal(
            proposal: proposal,
            runID: record.runID,
            goalID: goal.id,
            traceID: record.traceID,
            cycleIndex: 1,
            lease: lease
        )

        #expect(!obs.succeeded)
        #expect(attempt.status == .unresolved)
        #expect(attempt.status != .failed)
    }
}
