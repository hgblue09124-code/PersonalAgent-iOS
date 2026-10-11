import XCTest
@testable import PATerminal
@testable import PASkills
@testable import PAWorkspace

final class TerminalSkillBridgeTests: XCTestCase {

    func testSkillListUsesRuntimeDiscovery() async throws {
        let skill = SkillDefinition(
            identity: "calculator",
            scope: "arithmetic",
            input: "expression",
            rule: "evaluate",
            output: "integer",
            permissions: ["MODEL_ACCESS"],
            dependencies: ["calculator"],
            version: "1"
        )
        let runtime = SkillRuntime(skills: [skill])
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let registry = BuiltinCommandRegistry.make(skillRuntime: runtime)

        let execution = try await session.execute("skill list calc", registry: registry)
        let output = await session.outputs()
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertTrue(output.last?.text.contains("calculator") == true)
        XCTAssertTrue(output.last?.text.contains("arithmetic") == true)
    }

    func testSkillAwareHelpListsDiscoveryAndExecution() async throws {
        let runtime = SkillRuntime()
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let registry = BuiltinCommandRegistry.make(skillRuntime: runtime)
        let result = try await registry.execute(AgentCommand(name: "help"), context: CommandContext(workspace: workspace))
        XCTAssertTrue(result.stdout.contains("skill"))
    }

    func testSkillCommandUsesSkillRuntime() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { input in input == "187 * 43" ? "8041" : "0" }])
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let execution = try await session.execute(#"skill run calculator "187 * 43""#, registry: BuiltinCommandRegistry.make(skillRuntime: runtime))
        let output = await session.outputs()
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertEqual(output.last?.text, "8041")
    }
}
