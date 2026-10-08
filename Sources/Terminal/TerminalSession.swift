import Foundation

public enum TerminalExitState: Sendable, Equatable {
    case running
    case succeeded
    case failed
    case cancelled
}

public struct TerminalOutput: Sendable, Equatable {
    public enum Stream: Sendable, Equatable { case stdout, stderr }
    public let stream: Stream
    public let text: String
    public let timestamp: Date
    public init(stream: Stream, text: String, timestamp: Date = Date()) { self.stream = stream; self.text = text; self.timestamp = timestamp }
}

public struct TerminalCommandExecution: Sendable, Equatable {
    public let id: UUID
    public let command: AgentCommand
    public let startedAt: Date
    public let finishedAt: Date?
    public let exitCode: Int32?
    public let state: TerminalExitState
    public init(id: UUID = UUID(), command: AgentCommand, startedAt: Date = Date(), finishedAt: Date? = nil, exitCode: Int32? = nil, state: TerminalExitState = .running) {
        self.id = id; self.command = command; self.startedAt = startedAt; self.finishedAt = finishedAt; self.exitCode = exitCode; self.state = state
    }
}

public actor TerminalHistory {
    private var commands: [AgentCommand] = []
    private let limit: Int
    public init(limit: Int = 100) { self.limit = max(1, limit) }
    public func append(_ command: AgentCommand) { commands.append(command); if commands.count > limit { commands.removeFirst(commands.count - limit) } }
    public func all() -> [AgentCommand] { commands }
    public func clear() { commands.removeAll(keepingCapacity: true) }
}

public actor TerminalSession {
    public let id: UUID
    public let context: CommandContext
    public let history: TerminalHistory
    private var executions: [UUID: TerminalCommandExecution] = [:]
    private var output: [TerminalOutput] = []
    private var currentDirectory = "."

    public init(id: UUID = UUID(), context: CommandContext, history: TerminalHistory = TerminalHistory()) {
        self.id = id; self.context = context; self.history = history
    }

    public func workingDirectory() -> String { currentDirectory }
    public func setWorkingDirectory(_ path: String) { currentDirectory = path }

    public func execute(_ input: String, registry: CommandRegistry) async throws -> TerminalCommandExecution {
        let command = try CommandParser.parse(input)
        await history.append(command)
        let execution = TerminalCommandExecution(command: command)
        executions[execution.id] = execution
        do {
            let result = try await registry.execute(command, context: context)
            if !result.stdout.isEmpty { output.append(TerminalOutput(stream: .stdout, text: result.stdout)) }
            if !result.stderr.isEmpty { output.append(TerminalOutput(stream: .stderr, text: result.stderr)) }
            let state: TerminalExitState = result.success ? .succeeded : .failed
            let finished = TerminalCommandExecution(id: execution.id, command: command, startedAt: execution.startedAt, finishedAt: Date(), exitCode: result.exitCode, state: state)
            executions[execution.id] = finished
            return finished
        } catch is CancellationError {
            let finished = TerminalCommandExecution(id: execution.id, command: command, startedAt: execution.startedAt, finishedAt: Date(), exitCode: nil, state: .cancelled)
            executions[execution.id] = finished
            throw CancellationError()
        }
    }

    public func outputs() -> [TerminalOutput] { output }
    public func execution(_ id: UUID) -> TerminalCommandExecution? { executions[id] }
}
