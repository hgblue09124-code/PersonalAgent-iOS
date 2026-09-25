import Foundation
import PAFoundation
import PAObservability
import PAEvents

/// Events emitted across the App Session boundary.
public enum AgentSessionEvent: Sendable {
    case inputReceived(statement: String, timestamp: Date)
    case goalSubmitted(GoalID, statement: String)
    case stateChanged(from: AgentState, to: AgentState)
    case executionError(String)
}

/// Explicit boundary contract between the application UI / App runtime and the Agent OS runtime.
/// The application interacts strictly through this contract and must NEVER duplicate or own `AgentState`.
public protocol AgentSession: Sendable {
    /// Agent identity associated with this session.
    var agentIdentity: AgentIdentity { get }

    /// Current live agent state queried directly from AgentRuntime.
    func currentState() async -> AgentState

    /// Current active goals queried directly from AgentRuntime.
    func activeGoals() async -> [Goal]

    /// Submit user input/goal statement into the Agent runtime.
    @discardableResult
    func submitInput(_ statement: String) async throws -> GoalID

    /// Session controls delegating directly to AgentRuntime lifecycle machine.
    func start() async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws

    /// Stream of session events emitted during runtime coordination.
    var sessionEvents: AsyncStream<AgentSessionEvent> { get }
}

/// Canonical thread-safe implementation of `AgentSession` wrapping `AgentRuntime`.
public final class DefaultAgentSession: AgentSession, @unchecked Sendable {
    private let runtime: AgentRuntime
    private let logger: any AgentLogger
    private let continuation: AsyncStream<AgentSessionEvent>.Continuation
    public let sessionEvents: AsyncStream<AgentSessionEvent>

    public init(runtime: AgentRuntime, logger: any AgentLogger = NullLoggerBridge()) {
        self.runtime = runtime
        self.logger = logger

        var localContinuation: AsyncStream<AgentSessionEvent>.Continuation!
        self.sessionEvents = AsyncStream { cont in
            localContinuation = cont
        }
        self.continuation = localContinuation
    }

    public var agentIdentity: AgentIdentity {
        runtime.identity
    }

    public func currentState() async -> AgentState {
        await runtime.currentState()
    }

    public func activeGoals() async -> [Goal] {
        await runtime.goals()
    }

    @discardableResult
    public func submitInput(_ statement: String) async throws -> GoalID {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KernelError.emptyGoalStatement
        }

        continuation.yield(.inputReceived(statement: trimmed, timestamp: Date()))

        let goal = Goal(statement: trimmed)
        try await runtime.submit(goal: goal)
        continuation.yield(.goalSubmitted(goal.id, statement: trimmed))
        return goal.id
    }

    public func start() async throws {
        let oldState = await runtime.currentState()
        try await runtime.start()
        let newState = await runtime.currentState()
        continuation.yield(.stateChanged(from: oldState, to: newState))
    }

    public func pause() async throws {
        let oldState = await runtime.currentState()
        try await runtime.pause()
        let newState = await runtime.currentState()
        continuation.yield(.stateChanged(from: oldState, to: newState))
    }

    public func resume() async throws {
        let oldState = await runtime.currentState()
        try await runtime.resume()
        let newState = await runtime.currentState()
        continuation.yield(.stateChanged(from: oldState, to: newState))
    }

    public func stop() async throws {
        let oldState = await runtime.currentState()
        try await runtime.stop()
        let newState = await runtime.currentState()
        continuation.yield(.stateChanged(from: oldState, to: newState))
    }
}
