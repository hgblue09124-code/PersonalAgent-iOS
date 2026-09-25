import Foundation

public enum ExecutionEventKind: String, Sendable, Codable {
    case perceptionReceived, goalSubmitted, contextBuilt, planProduced, actionProposed
    case actionAuthorized, actionDenied, actionExecuted, observationProduced, evaluationCompleted
    case reflectionCompleted, stateUpdated, toolCalled, providerInvoked, verificationCompleted
    case approvalRequested, approvalResolved, failed
    case runtimeInitialized, runtimeStarted, runtimePaused, runtimeResumed, runtimeStopped
    case goalActivated, goalBlocked, goalCompleted, goalAborted, commandRejected
    case providerConfigured, providerReady, providerCompleted, providerFailed, providerCancelled
    case moduleInvoked, moduleCompleted, moduleFailed, moduleCancelled
    case memoryCaptured, memoryUpdated, memoryForgotten, memoryQueried
}
public struct ExecutionEvent: Sendable, Codable, Equatable {
    public let id: EventID
    public let traceID: TraceID
    public let kind: ExecutionEventKind
    public let timestamp: Date
    public let payload: [String: String]
    public init(id: EventID = EventID(), traceID: TraceID, kind: ExecutionEventKind,
                timestamp: Date = Date(), payload: [String: String] = [:]) {
        self.id=id; self.traceID=traceID; self.kind=kind; self.timestamp=timestamp; self.payload=payload
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
public protocol ExecutionTrace: Sendable { var traceID: TraceID { get } }
public protocol ExecutionReplaying: Sendable { func replay(traceID: TraceID) async throws }
public struct EventObservabilityBridge { public static let category = "events" }
