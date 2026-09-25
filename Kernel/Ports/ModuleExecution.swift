public struct ModuleInvocation: Sendable, Equatable {
    public let moduleID: ModuleID
    public let input: ModulePayload
    public let timeoutNanoseconds: UInt64?
    public init(moduleID: ModuleID, input: ModulePayload, timeoutNanoseconds: UInt64? = nil) {
        self.moduleID = moduleID; self.input = input; self.timeoutNanoseconds = timeoutNanoseconds
    }
}
public struct ModuleResult: Sendable, Equatable {
    public let moduleID: ModuleID
    public let output: ModulePayload
    public let state: ModuleExecutionState
    public init(moduleID: ModuleID, output: ModulePayload, state: ModuleExecutionState = .completed) {
        self.moduleID = moduleID; self.output = output; self.state = state
    }
}
public protocol ModuleExecuting: Sendable {
    func execute(_ invocation: ModuleInvocation) async throws -> ModuleResult
}
