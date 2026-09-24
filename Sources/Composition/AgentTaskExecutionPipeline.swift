import Foundation
import PAFoundation
import PAKernel
import PAEvents
import PACognition
import PAAgency

public enum ExecutionStepStatus: String, Sendable, Equatable, Codable {
    case pending = "…"
    case inProgress = "●"
    case completed = "✓"
    case failed = "✗"
}

public enum AgentTaskExecutionState: String, Sendable, Equatable, Codable {
    case idle
    case running
    case completed
    case failed
}

public struct AgentTaskExecutionPipeline: Sendable, Equatable {
    public var currentTask: String
    public var state: AgentTaskExecutionState
    public var reasoningStatus: ExecutionStepStatus
    public var actionStatus: ExecutionStepStatus
    public var observationStatus: ExecutionStepStatus
    public var verificationStatus: ExecutionStepStatus
    public var reasoningSummary: String?
    public var actionSummary: String?
    public var observationSummary: String?
    public var verificationSummary: String?
    public var resultSummary: String?
    public var userSafeFailureReason: String?
    public var validationError: String?

    public init(
        currentTask: String = "",
        state: AgentTaskExecutionState = .idle,
        reasoningStatus: ExecutionStepStatus = .pending,
        actionStatus: ExecutionStepStatus = .pending,
        observationStatus: ExecutionStepStatus = .pending,
        verificationStatus: ExecutionStepStatus = .pending,
        reasoningSummary: String? = nil,
        actionSummary: String? = nil,
        observationSummary: String? = nil,
        verificationSummary: String? = nil,
        resultSummary: String? = nil,
        userSafeFailureReason: String? = nil,
        validationError: String? = nil
    ) {
        self.currentTask = currentTask
        self.state = state
        self.reasoningStatus = reasoningStatus
        self.actionStatus = actionStatus
        self.observationStatus = observationStatus
        self.verificationStatus = verificationStatus
        self.reasoningSummary = reasoningSummary
        self.actionSummary = actionSummary
        self.observationSummary = observationSummary
        self.verificationSummary = verificationSummary
        self.resultSummary = resultSummary
        self.userSafeFailureReason = userSafeFailureReason
        self.validationError = validationError
    }

    public static func validateTask(_ statement: String) -> String? {
        if statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a task before running."
        }
        return nil
    }

    public static func startPipeline(task: String) -> AgentTaskExecutionPipeline {
        AgentTaskExecutionPipeline(
            currentTask: task.trimmingCharacters(in: .whitespacesAndNewlines),
            state: .running,
            reasoningStatus: .inProgress,
            actionStatus: .pending,
            observationStatus: .pending,
            verificationStatus: .pending,
            reasoningSummary: "Reasoning about task..."
        )
    }

    public mutating func updateFromEvents(_ events: [ExecutionEvent], goalID: GoalID, eval: Evaluation) {
        let goalEvents = events.filter { $0.payload["goalID"] == goalID.rawValue }

        if goalEvents.contains(where: { $0.kind == .planProduced }) {
            reasoningStatus = .completed
            reasoningSummary = "Plan produced"
            actionStatus = .inProgress
        }

        let verificationAccepted: Bool
        if let verificationEvent = goalEvents.first(where: { $0.kind == .verificationCompleted }) {
            let accepted = verificationEvent.payload["accepted"] == "true"
            verificationAccepted = accepted
            verificationStatus = accepted ? .completed : .failed
            verificationSummary = verificationEvent.payload["notes"] ?? (accepted ? "Verified" : "Verification rejected")
        } else {
            verificationAccepted = false
            verificationStatus = .failed
            verificationSummary = "Verification evidence missing"
        }

        if goalEvents.contains(where: { $0.kind == .actionExecuted }) {
            actionStatus = .completed
            actionSummary = "Action executed"
            observationStatus = .inProgress
        }

        if let obsEvent = goalEvents.first(where: { $0.kind == .observationProduced }) {
            let succeeded = obsEvent.payload["succeeded"] == "true"
            observationStatus = succeeded ? .completed : .failed
            observationSummary = obsEvent.payload["summary"] ?? (succeeded ? "Observation returned" : "Observation failed")
        }

        if eval.disposition == .complete && verificationAccepted {
            state = .completed
            reasoningStatus = .completed
            actionStatus = .completed
            observationStatus = .completed
            verificationStatus = .completed
            resultSummary = eval.reason
        } else {
            state = .failed
            if reasoningStatus == .inProgress { reasoningStatus = .failed }
            else if actionStatus == .inProgress { actionStatus = .failed }
            else if observationStatus == .inProgress { observationStatus = .failed }
            else if verificationStatus == .inProgress { verificationStatus = .failed }
            userSafeFailureReason = eval.disposition == .complete && !verificationAccepted
                ? "Verification evidence missing"
                : eval.reason
        }
    }
}
