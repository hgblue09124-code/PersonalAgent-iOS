import XCTest
import PAKernel
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
        let registry = BuiltinCommandRegistry.make(skillRuntime: runtime, authorizer: AllowTerminalAuthorizer())

        let execution = try await session.execute("skill list calc", registry: registry)
        let output = await session.outputs()
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertTrue(output.last?.text.contains("calculator") == true)
        XCTAssertTrue(output.last?.text.contains("arithmetic") == true)
    }

    func testSkillAwareHelpListsDiscoveryAndExecution() async throws {
        let runtime = SkillRuntime()
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let registry = BuiltinCommandRegistry.make(skillRuntime: runtime, authorizer: AllowTerminalAuthorizer())
        let result = try await registry.execute(AgentCommand(name: "help"), context: CommandContext(workspace: workspace))
        XCTAssertTrue(result.stdout.contains("skill"))
    }

    func testSkillRunWithoutInjectedPolicyFailsClosed() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: [], dependencies: [], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { _ in "must not execute" }])
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))

        let execution = try await session.execute("skill run calculator 1+1", registry: BuiltinCommandRegistry.make(skillRuntime: runtime, authorizer: AllowTerminalAuthorizer()))
        let output = await session.outputs()

        XCTAssertEqual(execution.state, .failed)
        XCTAssertTrue(output.last?.text.contains("explicit policy is required") == true)
    }

    func testSkillCommandUsesSkillRuntime() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { input in input == "187 * 43" ? "8041" : "0" }])
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = TerminalSession(context: CommandContext(workspace: workspace))
        let execution = try await session.execute(#"skill run calculator "187 * 43""#, registry: BuiltinCommandRegistry.make(skillRuntime: runtime, authorizer: AllowTerminalAuthorizer(), executeSkill: { request in try await runtime.run(request, policy: AllowTerminalSkillPolicy()) }))
        let output = await session.outputs()
        XCTAssertEqual(execution.state, .succeeded)
        XCTAssertEqual(output.last?.text, "8041")
    }
}


private struct AllowTerminalSkillPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("test-only explicit grant") }
}


private struct AllowTerminalAuthorizer: TerminalCommandAuthorizing {
    func authorize(_ capabilities: Set<TerminalCapability>, summary: String) async -> Bool { true }
}
