import Foundation
import PAWorkspace

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
    private var currentDirectory = ""

    public init(id: UUID = UUID(), context: CommandContext, history: TerminalHistory = TerminalHistory()) {
        self.id = id; self.context = context; self.history = history
    }

    public func workingDirectory() -> String { currentDirectory }
    public func setWorkingDirectory(_ path: String) { currentDirectory = path }

    public func execute(_ input: String, registry: CommandRegistry) async throws -> TerminalCommandExecution {
        let parsed = try CommandParser.parse(input)
        let command: AgentCommand
        if parsed.name == "cd" {
            guard parsed.arguments.count <= 1 else { throw CommandError.invalidArguments("cd [path]") }
            let target = parsed.arguments.first ?? ""
            let next = try await resolveWorkingDirectory(target)
            currentDirectory = next
            command = parsed
        } else {
            command = try await commandInWorkingDirectory(parsed)
        }
        await history.append(command)
        let execution = TerminalCommandExecution(command: command)
        executions[execution.id] = execution
        do {
            let result: CommandResult
            if command.name == "cd" {
                result = CommandResult()
            } else {
                let executionContext = CommandContext(workspace: context.workspace, workingDirectory: currentDirectory)
                result = try await registry.execute(command, context: executionContext)
            }
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
        } catch {
            let finished = TerminalCommandExecution(id: execution.id, command: command, startedAt: execution.startedAt, finishedAt: Date(), exitCode: 1, state: .failed)
            executions[execution.id] = finished
            throw error
        }
    }

    private func resolveWorkingDirectory(_ path: String) async throws -> String {
        let candidate = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return "" }

        let resolved = try resolveTerminalPath(candidate)
        guard try await context.workspace.metadata(at: resolved).isDirectory else {
            throw AgentWorkspaceError.notDirectory(candidate)
        }
        return resolved
    }

    private func commandInWorkingDirectory(_ command: AgentCommand) throws -> AgentCommand {
        guard !currentDirectory.isEmpty else { return command }
        let pathArgumentIndices: Set<Int>
        switch command.name {
        case "ls", "cat", "head", "tail", "mkdir", "touch", "rm", "find":
            pathArgumentIndices = [0]
        case "grep":
            pathArgumentIndices = [1]
        case "cp", "mv":
            pathArgumentIndices = [0, 1]
        default:
            return command
        }

        let args = try command.arguments.enumerated().map { index, arg in
            guard pathArgumentIndices.contains(index), !arg.hasPrefix("/"), !arg.isEmpty, !arg.contains(":") else {
                return arg
            }
            return try resolveTerminalPath(arg)
        }
        return AgentCommand(name: command.name, arguments: args)
    }

    private func resolveTerminalPath(_ path: String) throws -> String {
        let normalized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else {
            throw AgentWorkspaceError.invalidPath(path)
        }

        var components = currentDirectory.split(separator: "/").map(String.init)
        for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw AgentWorkspaceError.escapesSandbox
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }

    public func outputs() -> [TerminalOutput] { output }
    public func execution(_ id: UUID) -> TerminalCommandExecution? { executions[id] }
    public func executionHistory() -> [TerminalCommandExecution] {
        executions.values.sorted { $0.startedAt < $1.startedAt }
    }
}
