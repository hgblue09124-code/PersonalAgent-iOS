import Foundation
import PAFoundation
import PAPolicy
import PAAgency
import PACognition
import PAObservability
import PAEvents

public struct AgentIdentity: Hashable, Sendable, Codable {
    public let id: AgentID
    public let displayName: String
    public let createdAt: Date

    public init(id: AgentID = AgentID(), displayName: String, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

public enum GoalStatus: String, Sendable, Codable {
    case proposed
    case active
    case blocked
    case completed
    case aborted
}

public struct Goal: Hashable, Sendable, Codable {
    public let id: GoalID
    public let statement: String
    public let createdAt: Date
    public var status: GoalStatus

    public init(
        id: GoalID = GoalID(),
        statement: String,
        createdAt: Date = Date(),
        status: GoalStatus = .proposed
    ) {
        self.id = id
        self.statement = statement
        self.createdAt = createdAt
        self.status = status
    }
}

public enum AgentLifecycle: String, Sendable, Codable {
    case created
    case starting
    case running
    case pausing
    case paused
    case stopping
    case stopped
    case failed
}

public struct AgentState: Sendable, Equatable, Codable {
    public var identity: AgentIdentity
    public var lifecycle: AgentLifecycle
    public var phase: AgentPhase
    public var activeGoalID: GoalID?

    public init(
        identity: AgentIdentity,
        lifecycle: AgentLifecycle = .created,
        phase: AgentPhase = .idle,
        activeGoalID: GoalID? = nil
    ) {
        self.identity = identity
        self.lifecycle = lifecycle
        self.phase = phase
        self.activeGoalID = activeGoalID
    }
}

/// Kernel coordinates. Views do not drive internals. LLM does not own this type.
public protocol AgentRuntimeCoordinating: Sendable {
    func currentState() async -> AgentState
    func submit(goal: Goal) async throws
    func abort(goalID: GoalID) async throws
}

public protocol AgentLifecycleManaging: Sendable {
    func start() async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
}
