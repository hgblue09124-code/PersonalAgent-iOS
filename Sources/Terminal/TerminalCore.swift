import Foundation
import PAWorkspace

public struct AgentCommand: Sendable, Equatable {
    public let name: String
    public let arguments: [String]
    public init(name: String, arguments: [String] = []) { self.name = name; self.arguments = arguments }
}

public enum CommandError: Error, Sendable, Equatable {
    case emptyCommand
    case unterminatedQuote
    case invalidEscape
    case unknownCommand(String)
    case invalidArguments(String)
}

public struct CommandResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var success: Bool { exitCode == 0 }
    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) { self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode }
}

public struct CommandContext: Sendable {
    public let workspace: AgentWorkspace
    public init(workspace: AgentWorkspace) { self.workspace = workspace }
}

public typealias CommandHandler = @Sendable (AgentCommand, CommandContext) async throws -> CommandResult

public struct CommandRegistry: Sendable {
    private let handlers: [String: CommandHandler]
    public init(handlers: [String: CommandHandler] = [:]) { self.handlers = handlers }
    public func registering(_ name: String, handler: @escaping CommandHandler) -> CommandRegistry {
        var copy = handlers; copy[name] = handler; return CommandRegistry(handlers: copy)
    }
    public func contains(_ name: String) -> Bool { handlers[name] != nil }
    public func execute(_ command: AgentCommand, context: CommandContext) async throws -> CommandResult {
        guard let handler = handlers[command.name] else { throw CommandError.unknownCommand(command.name) }
        return try await handler(command, context)
    }
}

public enum CommandParser {
    public static func parse(_ input: String) throws -> AgentCommand {
        let tokens = try tokenize(input)
        guard let name = tokens.first else { throw CommandError.emptyCommand }
        return AgentCommand(name: name, arguments: Array(tokens.dropFirst()))
    }

    private static func tokenize(_ input: String) throws -> [String] {
        var result: [String] = [], current = "", quote: Character?, escaping = false, started = false
        for ch in input {
            if escaping { current.append(ch); escaping = false; started = true; continue }
            if ch == "\\" { escaping = true; started = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                started = true; continue
            }
            if ch == "'" || ch == "\"" { quote = ch; started = true; continue }
            if ch.isWhitespace {
                if started { result.append(current); current = ""; started = false }
            } else { current.append(ch); started = true }
        }
        if escaping { throw CommandError.invalidEscape }
        if quote != nil { throw CommandError.unterminatedQuote }
        if started { result.append(current) }
        return result
    }
}

public struct BuiltinCommandRegistry {
    public static func make() -> CommandRegistry {
        let names = ["pwd", "ls", "cd", "cat", "head", "tail", "mkdir", "touch", "cp", "mv", "rm", "find", "grep", "clear", "help", "agent", "skill", "module", "memory", "model", "provider", "workspace", "sync"]
        var registry = CommandRegistry()
        for name in names {
            registry = registry.registering(name) { command, _ in
                CommandResult(stderr: "command '\(command.name)' is registered but not implemented", exitCode: 127)
            }
        }
        return registry
    }

    public static func make(skillRuntime: SkillRuntime) -> CommandRegistry {
        var registry = make()
        registry = registry.registering("skill") { command, _ in
            guard command.arguments.count >= 3, command.arguments[0] == "run" else {
                throw CommandError.invalidArguments("skill run <skill> <input>")
            }
            let input = command.arguments.dropFirst(2).joined(separator: " ")
            let result = try await skillRuntime.run(
                SkillExecutionRequest(
                    skillID: String(command.arguments[1]),
                    moduleID: String(command.arguments[1]),
                    input: input
                )
            )
            return CommandResult(stdout: result)
        }
        return registry
    }
}
