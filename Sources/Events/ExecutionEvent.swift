import Foundation
import PAFoundation
import PAObservability

public enum ExecutionEventKind: String, Sendable, Codable {
    case goalSubmitted
    case contextBuilt
    case planProduced
    case actionProposed
    case toolCalled
    case providerInvoked
    case verificationCompleted
    case stateUpdated
    case approvalRequested
    case approvalResolved
    case failed
    // M1 kernel runtime
    case runtimeInitialized
    case runtimeStarted
    case runtimePaused
    case runtimeResumed
    case runtimeStopped
    case goalActivated
    case goalBlocked
    case goalCompleted
    case goalAborted
    case commandRejected
    // M2 provider runtime
    case providerConfigured
    case providerReady
    case providerCompleted
    case providerFailed
    case providerCancelled
}

public struct ExecutionEvent: Sendable, Codable, Equatable {
    public let id: EventID
    public let traceID: TraceID
    public let kind: ExecutionEventKind
    public let timestamp: Date
    public let payload: [String: String]

    public init(
        id: EventID = EventID(),
        traceID: TraceID,
        kind: ExecutionEventKind,
        timestamp: Date = Date(),
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.traceID = traceID
        self.kind = kind
        self.timestamp = timestamp
        self.payload = payload
    }
}

public protocol EventLog: Sendable {
    func append(_ event: ExecutionEvent) async throws
    func events(for traceID: TraceID) async throws -> [ExecutionEvent]
}

public protocol ExecutionTrace: Sendable {
    var traceID: TraceID { get }
}

/// Replay is designed in M0. Implementation may stay minimal until M8.
public protocol ExecutionReplaying: Sendable {
    func replay(traceID: TraceID) async throws
}

public struct EventObservabilityBridge {
    public static let category = "events"
}
