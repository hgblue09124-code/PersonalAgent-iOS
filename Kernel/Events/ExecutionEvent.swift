import Foundation
import PAFoundation
import PAObservability

public enum ExecutionEventKind: String, Sendable, Codable {
    case perceptionReceived
    case goalSubmitted
    case contextBuilt
    case planProduced
    case actionProposed
    case actionAuthorized
    case actionDenied
    case actionExecuted
    case observationProduced
    case evaluationCompleted
    case reflectionCompleted
    case stateUpdated
    case toolCalled
    case providerInvoked
    case verificationCompleted
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
    // M3 module runtime
    case moduleInvoked
    case moduleCompleted
    case moduleFailed
    case moduleCancelled
    // M4 memory runtime
    case memoryCaptured
    case memoryUpdated
    case memoryForgotten
    case memoryQueried
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
    func allEvents() async throws -> [ExecutionEvent]
}

extension EventLog {
    public func allEvents() async throws -> [ExecutionEvent] {
        try await events(for: TraceID(rawValue: "all"))
    }
}

public protocol ExecutionTrace: Sendable {
    var traceID: TraceID { get }
}

public protocol ExecutionReplaying: Sendable {
    func replay(traceID: TraceID) async throws
}

public struct EventObservabilityBridge {
    public static let category = "events"
}
