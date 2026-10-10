import XCTest
import PAWorkspace
@testable import PATerminal

final class TerminalCoreTests: XCTestCase {
    func testParserPreservesQuotedArguments() throws {
        let command = try CommandParser.parse(#"skill run calculator "187 * 43""#)
        XCTAssertEqual(command.name, "skill")
        XCTAssertEqual(command.arguments, ["run", "calculator", "187 * 43"])
    }
    func testCommandErrorsHaveActionableLocalizedDescriptions() {
        XCTAssertEqual(CommandError.emptyCommand.localizedDescription, "Enter a command.")
        XCTAssertEqual(
            CommandError.unterminatedQuote.localizedDescription,
            "Unterminated quote. Close the quote and try again."
        )
        XCTAssertEqual(
            CommandError.invalidEscape.localizedDescription,
            "The command ends with an incomplete escape. Add the escaped character or remove the trailing backslash."
        )
        XCTAssertEqual(
            CommandError.unknownCommand("missing").localizedDescription,
            "Unknown command: missing. Type 'help' to list available commands."
        )
        XCTAssertEqual(
            CommandError.invalidArguments("cat <path>").localizedDescription,
            "Invalid arguments. Usage: cat <path>"
        )
    }

    func testParserRejectsTrailingEscape() {
        XCTAssertThrowsError(try CommandParser.parse("cat file\\"))
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
        let copiedExists = try await workspace.exists(at: "workspace/test/c.txt")
        XCTAssertTrue(copiedExists)
        _ = try await registry.execute(AgentCommand(name: "rm", arguments: ["workspace/test/c.txt"]), context: context)
        let removedExists = try await workspace.exists(at: "workspace/test/c.txt")
        XCTAssertFalse(removedExists)
    }

    func testFindRecursesAndFiltersByName() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/project/nested")
        try await workspace.writeFile("needle\n", to: "workspace/project/nested/notes.md")
        try await workspace.writeFile("other\n", to: "workspace/project/readme.txt")

        let registry = BuiltinCommandRegistry.make()
        let result = try await registry.execute(
            AgentCommand(name: "find", arguments: ["workspace/project", ".md"]),
            context: CommandContext(workspace: workspace)
        )
        XCTAssertEqual(result.stdout, "workspace/project/nested/notes.md\n")
    }

    func testFindFailsClosedOnDirectorySymlinkCycles() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: rootURL)
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/tree")
        let link = rootURL.appendingPathComponent("workspace/tree/loop")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: rootURL.appendingPathComponent("workspace/tree").path
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        do {
            let result = try await BuiltinCommandRegistry.make().execute(
                AgentCommand(name: "find", arguments: ["workspace/tree"]),
                context: CommandContext(workspace: workspace)
            )
            XCTAssertEqual(result.stdout, "workspace/tree/loop\n")
        } catch let error as CommandError {
            XCTAssertEqual(error, .invalidArguments("find exceeded maximum directory depth (64)"))
        }
    }

    func testGrepReturnsMatchingLinesAndLineNumbers() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.writeFile("first\nNeedle here\nlast needle\n", to: "workspace/log.txt")

        let result = try await BuiltinCommandRegistry.make().execute(
            AgentCommand(name: "grep", arguments: ["needle", "workspace/log.txt"]),
            context: CommandContext(workspace: workspace)
        )
        XCTAssertEqual(result.stdout, "2:Needle here\n3:last needle\n")
    }

    func testWorkspaceCommandsReadWriteListAndRemoveFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: rootURL)
        try await workspace.prepare()
        let registry = BuiltinCommandRegistry.make()
        let context = CommandContext(workspace: workspace)

        let status = try await registry.execute(AgentCommand(name: "workspace", arguments: ["status"]), context: context)
        XCTAssertEqual(status.stdout, rootURL.path + "\n")

        _ = try await registry.execute(AgentCommand(name: "workspace", arguments: ["write", "workspace/note.md", "hello", "AgentOS"]), context: context)
        let read = try await registry.execute(AgentCommand(name: "workspace", arguments: ["read", "workspace/note.md"]), context: context)
        XCTAssertEqual(read.stdout, "hello AgentOS")

        let list = try await registry.execute(AgentCommand(name: "workspace", arguments: ["list", "workspace"]), context: context)
        XCTAssertTrue(list.stdout.contains("workspace/note.md"))
        _ = try await registry.execute(AgentCommand(name: "workspace", arguments: ["remove", "workspace/note.md"]), context: context)
        let exists = try await workspace.exists(at: "workspace/note.md")
        XCTAssertFalse(exists)
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
        let workingDirectory = await session.workingDirectory()
        XCTAssertEqual(workingDirectory, "workspace/project")
        let history = await session.history.all()
        XCTAssertTrue(history.contains(AgentCommand(name: "cd", arguments: ["workspace/project"])))
        _ = try await session.execute("touch file.txt", registry: BuiltinCommandRegistry.make())
        let fileExists = try await workspace.exists(at: "workspace/project/file.txt")
        XCTAssertTrue(fileExists)
    }

    func testSessionCdResolvesParentWithoutEscapingSandbox() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/project")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let registry = BuiltinCommandRegistry.make()

        _ = try await session.execute("cd workspace/project", registry: registry)
        _ = try await session.execute("cd ..", registry: registry)
        let workingDirectory = await session.workingDirectory()
        XCTAssertEqual(workingDirectory, "workspace")

        _ = try await session.execute("cd project", registry: registry)
        try await workspace.writeFile("x", to: "workspace/project/source.txt")
        _ = try await session.execute("cp source.txt ../backup.txt", registry: registry)

        let backupExists = try await workspace.exists(at: "workspace/backup.txt")
        let escapedBackupExists = try await workspace.exists(at: "backup.txt")
        XCTAssertTrue(backupExists)
        XCTAssertFalse(escapedBackupExists)
    }

    func testSessionCdRejectsFileTarget() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await workspace.prepare()
        try await workspace.writeFile("x", to: "workspace/file.txt")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        do { _ = try await session.execute("cd workspace/file.txt", registry: BuiltinCommandRegistry.make()); XCTFail("cd to file must fail") } catch { }
    }

    func testPwdUsesSessionWorkingDirectory() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: rootURL)
        try await workspace.prepare()
        try await workspace.createDirectory(at: "workspace/project")
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let registry = BuiltinCommandRegistry.make()
        _ = try await session.execute("cd workspace/project", registry: registry)
        _ = try await session.execute("pwd", registry: registry)
        let outputs = await session.outputs()
        XCTAssertEqual(outputs.last?.text, rootURL.appendingPathComponent("workspace/project").path + "\n")
    }

    func testBuiltinSurfaceIsRegistered() {
        let registry = BuiltinCommandRegistry.make()
        XCTAssertTrue(registry.contains("pwd")); XCTAssertTrue(registry.contains("skill")); XCTAssertTrue(registry.contains("sync"))
    }
}
