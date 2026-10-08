import XCTest
@testable import PATerminal

final class TerminalCoreTests: XCTestCase {
    func testParserPreservesQuotedArguments() throws {
        let command = try CommandParser.parse(#"skill run calculator "187 * 43""#)
        XCTAssertEqual(command.name, "skill")
        XCTAssertEqual(command.arguments, ["run", "calculator", "187 * 43"])
    }
    func testParserRejectsUnterminatedQuote() {
        XCTAssertThrowsError(try CommandParser.parse("cat \"broken"))
    }
    func testRegistryRejectsUnknownCommand() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let context = CommandContext(workspace: workspace)
        do { _ = try await BuiltinCommandRegistry.make().execute(AgentCommand(name: "nope"), context: context); XCTFail("must reject") } catch { }
    }
    func testFilesystemBuiltinsExecute() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let context = CommandContext(workspace: workspace)
        let registry = BuiltinCommandRegistry.make()
        _ = try await registry.execute(AgentCommand(name: "mkdir", arguments: ["workspace/test"]), context: context)
        _ = try await registry.execute(AgentCommand(name: "touch", arguments: ["workspace/test/a.txt"]), context: context)
        _ = try await registry.execute(AgentCommand(name: "cp", arguments: ["workspace/test/a.txt", "workspace/test/b.txt"]), context: context)
        _ = try await registry.execute(AgentCommand(name: "mv", arguments: ["workspace/test/b.txt", "workspace/test/c.txt"]), context: context)
        XCTAssertTrue(try await workspace.exists(at: "workspace/test/c.txt"))
        _ = try await registry.execute(AgentCommand(name: "rm", arguments: ["workspace/test/c.txt"]), context: context)
        XCTAssertFalse(try await workspace.exists(at: "workspace/test/c.txt"))
    }

    func testHeadAndTailRejectInvalidCounts() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        let context = CommandContext(workspace: workspace)
        let registry = BuiltinCommandRegistry.make()
        try await workspace.writeFile("a\nb\nc\n", to: "workspace/lines.txt")
        do { _ = try await registry.execute(AgentCommand(name: "head", arguments: ["workspace/lines.txt", "0"]), context: context); XCTFail("zero count must fail") } catch { }
        do { _ = try await registry.execute(AgentCommand(name: "tail", arguments: ["workspace/lines.txt", "-1"]), context: context); XCTFail("negative count must fail") } catch { }
    }

    func testSessionCdPersistsWorkingDirectory() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/project")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        _ = try await session.execute("cd workspace/project", registry: BuiltinCommandRegistry.make())
        XCTAssertEqual(await session.workingDirectory(), "workspace/project")
        XCTAssertTrue((await session.history.all()).contains(AgentCommand(name: "cd", arguments: ["workspace/project"])))
        _ = try await session.execute("touch file.txt", registry: BuiltinCommandRegistry.make())
        XCTAssertTrue(try await workspace.exists(at: "workspace/project/file.txt"))
    }

    func testSessionCdRejectsFileTarget() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.writeFile("x", to: "workspace/file.txt")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        do { _ = try await session.execute("cd workspace/file.txt", registry: BuiltinCommandRegistry.make()); XCTFail("cd to file must fail") } catch { }
    }

    func testPwdUsesSessionWorkingDirectory() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/project")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let registry = BuiltinCommandRegistry.make()
        _ = try await session.execute("cd workspace/project", registry: registry)
        _ = try await session.execute("pwd", registry: registry)
        let outputs = await session.outputs()
        XCTAssertEqual(outputs.last?.text, workspace.rootURL.path + "\n")
    }

    func testBuiltinSurfaceIsRegistered() {
        let registry = BuiltinCommandRegistry.make()
        XCTAssertTrue(registry.contains("pwd")); XCTAssertTrue(registry.contains("skill")); XCTAssertTrue(registry.contains("sync"))
    }
}
