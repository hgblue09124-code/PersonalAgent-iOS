import Foundation
import PAFoundation
import PAKernel
import PACognition
import PAAgency

public enum RunState: String, Sendable, Codable, Equatable {
    case initialized
    case running
    case checkpointed
    case paused
    case recovering
    case completed
    case failed
    case interrupted
}

public struct RunRecord: Sendable, Codable, Equatable {
    public let runID: RunID
    public let sessionID: SessionID
    public let goalID: GoalID
    public let traceID: TraceID
    public var status: RunState
    public var currentCycle: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        runID: RunID = RunID(),
        sessionID: SessionID = SessionID(),
        goalID: GoalID,
        traceID: TraceID = TraceID(),
        status: RunState = .initialized,
        currentCycle: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.goalID = goalID
        self.traceID = traceID
        self.status = status
        self.currentCycle = currentCycle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ExecutionAttemptStatus: String, Sendable, Codable, Equatable {
    case notStarted = "NOT_STARTED"
    case startedUnknown = "STARTED_UNKNOWN"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case unresolved = "UNRESOLVED"
}

public struct ExecutionAttempt: Sendable, Codable, Equatable {
    public let attemptID: ExecutionAttemptID
    public let runID: RunID
    public let actionID: ActionID
    public let toolID: ToolID?
    public let idempotencyKey: String
    public var status: ExecutionAttemptStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var receiptRef: String?
    public var observationID: ActionID?
    public var eventID: EventID?

    public init(
        attemptID: ExecutionAttemptID = ExecutionAttemptID(),
        runID: RunID,
        actionID: ActionID,
        toolID: ToolID? = nil,
        idempotencyKey: String,
        status: ExecutionAttemptStatus = .notStarted,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        receiptRef: String? = nil,
        observationID: ActionID? = nil,
        eventID: EventID? = nil
    ) {
        self.attemptID = attemptID
        self.runID = runID
        self.actionID = actionID
        self.toolID = toolID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.receiptRef = receiptRef
        self.observationID = observationID
        self.eventID = eventID
    }
}

public struct ExecutionReceipt: Sendable, Codable, Equatable {
    public let receiptID: String
    public let attemptID: ExecutionAttemptID
    public let toolID: ToolID
    public let idempotencyKey: String
    public let timestamp: Date
    public let outputSummary: String
    public let rawOutputFields: [String: String]

    public init(
        receiptID: String = UUID().uuidString,
        attemptID: ExecutionAttemptID,
        toolID: ToolID,
        idempotencyKey: String,
        timestamp: Date = Date(),
        outputSummary: String,
        rawOutputFields: [String: String] = [:]
    ) {
        self.receiptID = receiptID
        self.attemptID = attemptID
        self.toolID = toolID
        self.idempotencyKey = idempotencyKey
        self.timestamp = timestamp
        self.outputSummary = outputSummary
        self.rawOutputFields = rawOutputFields
    }
}

public struct RunCheckpoint: Sendable, Codable, Equatable {
    public let checkpointID: UUID
    public let runID: RunID
    public let goalID: GoalID
    public let traceID: TraceID
    public let cycleIndex: Int
    public let timestamp: Date
    public let pendingProposals: [ActionProposal]
    public let completedObservations: [Observation]
    public let lastEvaluation: Evaluation?
    public let lastReflection: Reflection?

    public init(
        checkpointID: UUID = UUID(),
        runID: RunID,
        goalID: GoalID,
        traceID: TraceID,
        cycleIndex: Int,
        timestamp: Date = Date(),
        pendingProposals: [ActionProposal] = [],
        completedObservations: [Observation] = [],
        lastEvaluation: Evaluation? = nil,
        lastReflection: Reflection? = nil
    ) {
        self.checkpointID = checkpointID
        self.runID = runID
        self.goalID = goalID
        self.traceID = traceID
        self.cycleIndex = cycleIndex
        self.timestamp = timestamp
        self.pendingProposals = pendingProposals
        self.completedObservations = completedObservations
        self.lastEvaluation = lastEvaluation
        self.lastReflection = lastReflection
    }
}

public enum JournalStatus: String, Sendable, Codable, Equatable {
    case prepared
    case stateCommitted
    case auditCommitted
    case finalized
    case aborted
}

public struct StateJournalEntry: Sendable, Codable, Equatable {
    public let journalID: UUID
    public let runID: RunID
    public let goalID: GoalID
    public let targetStatus: GoalStatus
    public let eventID: EventID
    public let canonicalEventPayload: String
    public let evidence: [String: String]
    public var status: JournalStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        journalID: UUID = UUID(),
        runID: RunID,
        goalID: GoalID,
        targetStatus: GoalStatus,
        eventID: EventID = EventID(),
        canonicalEventPayload: String,
        evidence: [String: String] = [:],
        status: JournalStatus = .prepared,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.journalID = journalID
        self.runID = runID
        self.goalID = goalID
        self.targetStatus = targetStatus
        self.eventID = eventID
        self.canonicalEventPayload = canonicalEventPayload
        self.evidence = evidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum CapabilityLeaseError: Error, Sendable, Equatable {
    case maxStepsExceeded(current: Int, requested: Int, max: Int)
    case expired(expiresAt: Date, now: Date)
    case revoked
    case runIDMismatch(expected: RunID, actual: RunID)
}

public actor CapabilityLease {
    public let runID: RunID
    public let grantedAt: Date
    public let expiresAt: Date
    public let maxStepCount: Int
    private(set) public var currentStepCount: Int
    private(set) public var isRevoked: Bool

    public init(
        runID: RunID,
        grantedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(3600),
        maxStepCount: Int = 10,
        currentStepCount: Int = 0,
        isRevoked: Bool = false
    ) {
        self.runID = runID
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.maxStepCount = maxStepCount
        self.currentStepCount = currentStepCount
        self.isRevoked = isRevoked
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt
    }

    public func revoke() {
        isRevoked = true
    }

    public func consume(step: Int = 1, forRunID: RunID, now: Date = Date()) throws {
        guard forRunID == runID else {
            throw CapabilityLeaseError.runIDMismatch(expected: runID, actual: forRunID)
        }
        if isRevoked {
            throw CapabilityLeaseError.revoked
        }
        if isExpired(now: now) {
            throw CapabilityLeaseError.expired(expiresAt: expiresAt, now: now)
        }
        if currentStepCount + step > maxStepCount {
            throw CapabilityLeaseError.maxStepsExceeded(
                current: currentStepCount,
                requested: step,
                max: maxStepCount
            )
        }
        currentStepCount += step
    }
}

public enum EvidenceResolution: Sendable, Codable, Equatable {
    case completed(ExecutionReceipt)
    case notStarted
    case unknown
    case unavailable
}

public protocol ExecutionEvidenceResolver: Sendable {
    func resolve(
        attemptID: ExecutionAttemptID,
        idempotencyKey: String
    ) async throws -> EvidenceResolution
}

public enum ExecutionIdempotencyClass: String, Sendable, Codable, Equatable {
    case idempotent
    case nonIdempotent
}

public struct ExecutionTargetCapability: Sendable, Codable, Equatable {
    public let toolID: ToolID
    public let idempotencyClass: ExecutionIdempotencyClass
    public let supportsEvidenceResolution: Bool

    public init(
        toolID: ToolID,
        idempotencyClass: ExecutionIdempotencyClass,
        supportsEvidenceResolution: Bool
    ) {
        self.toolID = toolID
        self.idempotencyClass = idempotencyClass
        self.supportsEvidenceResolution = supportsEvidenceResolution
    }
}
