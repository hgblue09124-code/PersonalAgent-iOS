import XCTest
@testable import PASkills

final class SkillMarkdownContractTests: XCTestCase {
    func testParsesRequiredSkillContract() throws {
        let skill = try SkillMarkdownParser.parse("""
        identity: calculator
        scope: deterministic arithmetic
        input: expression
        rule: evaluate exactly once
        output: integer
        permissions: READ_WORKSPACE
        dependencies: calculator-module
        version: 1
        """)
        XCTAssertEqual(skill.identity, "calculator")
        XCTAssertEqual(skill.permissions, ["READ_WORKSPACE"])
        XCTAssertEqual(skill.version, "1")
    }

    func testMissingRuleFailsClosed() {
        XCTAssertThrowsError(try SkillMarkdownParser.parse("""
        identity: calculator
        scope: arithmetic
        input: expression
        output: integer
        permissions: READ_WORKSPACE
        dependencies: calculator-module
        version: 1
        """)) { error in
            XCTAssertEqual(error as? SkillDefinitionError, .missingField("rule"))
        }
    }
}
