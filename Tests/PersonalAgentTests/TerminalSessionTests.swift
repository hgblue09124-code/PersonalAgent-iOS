import XCTest
@testable import PATerminal
@testable import PAWorkspace

final class TerminalSessionTests: XCTestCase {
    func testSessionSharesKernelContextAndHistory() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let context = CommandContext(workspace: workspace)
        let session = TerminalSession(context: context)
        let registry = CommandRegistry().registering("echo") { command, _ in CommandResult(stdout: command.arguments.joined(separator: " ")) }
        let execution = try await session.execute("echo hello world", registry: registry)
        let outputs = await session.outputs()
        let history = await session.history.all()
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(outputs.first?.text, "hello world")
        XCTAssertEqual(history.count, 1)
    }

    func testThrownCommandMarksExecutionFailedInsteadOfLeavingItRunning() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let registry = CommandRegistry().registering("explode") { _, _ in
            throw CommandError.invalidArguments("simulated failure")
        }

        do {
            _ = try await session.execute("explode", registry: registry)
            XCTFail("command error must propagate")
        } catch let error as CommandError {
            XCTAssertEqual(error, .invalidArguments("simulated failure"))
        }

        let history = await session.history.all()
        let executions = await session.executionHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(executions.last?.state, .failed)
        XCTAssertEqual(executions.last?.exitCode, 1)
        XCTAssertNotNil(executions.last?.finishedAt)
    }

    func testOutputAndExecutionHistoryRemainBounded() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let session = TerminalSession(
            context: CommandContext(workspace: workspace),
            executionLimit: 2,
            outputLimit: 2
        )
        let registry = CommandRegistry().registering("echo") { command, _ in
            CommandResult(stdout: command.arguments.joined(separator: " "))
        }

        for value in ["one", "two", "three"] {
            _ = try await session.execute("echo " + value, registry: registry)
        }

        let outputs = await session.outputs()
        let executions = await session.executionHistory()
        XCTAssertEqual(outputs.map(\.text), ["two", "three"])
        XCTAssertEqual(executions.count, 2)
        XCTAssertEqual(executions.map { $0.command.arguments.first ?? "" }, ["two", "three"])
        XCTAssertTrue(executions.allSatisfy { $0.state == .succeeded })
    }

    func testUnknownCommandFailsClosed() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        do {
            _ = try await session.execute("missing", registry: CommandRegistry())
            XCTFail("unknown command must fail")
        } catch let error as CommandError {
            XCTAssertEqual(error, .unknownCommand("missing"))
        }
    }
    func testOutputHistoryIsBoundedByBytesAsWellAsEntryCount() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let session = TerminalSession(
            context: CommandContext(workspace: workspace),
            outputLimit: 20,
            outputByteLimit: 64
        )
        let registry = CommandRegistry().registering("echo") { command, _ in
            CommandResult(stdout: command.arguments.joined(separator: " "))
        }

        _ = try await session.execute("echo " + String(repeating: "a", count: 40), registry: registry)
        _ = try await session.execute("echo " + String(repeating: "b", count: 40), registry: registry)

        let outputs = await session.outputs()
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs[0].text.allSatisfy { $0 == "b" })
        XCTAssertLessThanOrEqual(outputs.reduce(0) { $0 + $1.text.utf8.count }, 64)
    }

}
