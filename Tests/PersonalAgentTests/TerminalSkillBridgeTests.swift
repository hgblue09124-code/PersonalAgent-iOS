import XCTest
@testable import PATerminal
@testable import PASkills
@testable import PAWorkspace

final class TerminalSkillBridgeTests: XCTestCase {
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
