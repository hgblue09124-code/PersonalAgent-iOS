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
    func testBuiltinSurfaceIsRegistered() {
        let registry = BuiltinCommandRegistry.make()
        XCTAssertTrue(registry.contains("pwd")); XCTAssertTrue(registry.contains("skill")); XCTAssertTrue(registry.contains("sync"))
    }
}
