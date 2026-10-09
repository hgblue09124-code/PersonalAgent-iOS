import XCTest
@testable import PASkills

final class SkillRuntimeTests: XCTestCase {
    func testSkillRunsThroughNamedModule() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { input in input == "187 * 43" ? "8041" : "0" }])
        let result = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "calculator", input: "187 * 43"))
        XCTAssertEqual(result, "8041")
    }

    func testMissingModuleFailsClosed() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill])
        do {
            _ = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "missing", input: "1 + 1"))
            XCTFail("missing module must fail")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .missingModule("missing"))
        }
    }
    func testDuplicateSkillIdentityKeepsFirstDefinitionWithoutTrapping() async throws {
        let first = SkillDefinition(identity: "duplicate", scope: "first scope", input: "input", rule: "first rule", output: "output", permissions: [], dependencies: [], version: "1")
        let second = SkillDefinition(identity: "duplicate", scope: "second scope", input: "input", rule: "second rule", output: "output", permissions: [], dependencies: [], version: "2")

        let runtime = SkillRuntime(skills: [first, second])
        let discovered = try await runtime.discover(query: "")

        XCTAssertEqual(discovered.filter { $0.id.rawValue == "duplicate" }.count, 1)
        XCTAssertEqual(discovered.first(where: { $0.id.rawValue == "duplicate" })?.description, "first scope")
    }

}
