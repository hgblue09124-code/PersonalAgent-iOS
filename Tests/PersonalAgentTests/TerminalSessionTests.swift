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
}
