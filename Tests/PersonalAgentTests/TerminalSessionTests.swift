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
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(await session.outputs().first?.text, "hello world")
        XCTAssertEqual(await session.history.all().count, 1)
    }

    func testFailedCommandProducesFailedExecution() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let execution = try await session.execute("missing", registry: CommandRegistry())
            .mapFailureToExecution()
        XCTAssertEqual(execution.state, .failed)
    }
}

private extension Result where Success == TerminalCommandExecution, Failure == Error {
    func mapFailureToExecution() throws -> Success {
        if case .success(let value) = self { return value }
        throw NSError(domain: "test", code: 1)
    }
}
