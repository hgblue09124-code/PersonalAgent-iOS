import Foundation
import XCTest
@testable import PASkills

final class PythonAgentPlanBridgeTests: XCTestCase {
    func testDecodesValidNonExecutableCreateFileProposal() throws {
        let json = """
        {
          "schema_version": 1,
          "kind": "propose_skill",
          "intent": {
            "kind": "create_file",
            "normalized_text": "Create file workspace/hello.txt with content: hello"
          },
          "message": "Proposal only",
          "missing_fields": [],
          "skill_id": "workspace.create-file",
          "arguments": {
            "path": "workspace/hello.txt",
            "content": "hello"
          },
          "is_executable": false
        }
        """
        let plan = try PythonAgentPlanEnvelope.decode(Data(json.utf8))
        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertEqual(plan.kind, .proposeSkill)
        XCTAssertEqual(plan.skillID, "workspace.create-file")
        XCTAssertEqual(plan.arguments["path"], .string("workspace/hello.txt"))
        XCTAssertEqual(plan.arguments["content"], .string("hello"))
        XCTAssertFalse(plan.isExecutable)
    }

    func testRejectsUnsupportedSchemaVersion() throws {
        let json = validProposal.replacingOccurrences(of: "\"schema_version\": 1", with: "\"schema_version\": 2")
        XCTAssertThrowsError(try PythonAgentPlanEnvelope.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? PythonAgentBridgeError, .unsupportedSchemaVersion(2))
        }
    }

    func testRejectsPlanThatClaimsExecutable() throws {
        let json = validProposal.replacingOccurrences(of: "\"is_executable\": false", with: "\"is_executable\": true")
        XCTAssertThrowsError(try PythonAgentPlanEnvelope.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? PythonAgentBridgeError, .executablePlanRejected)
        }
    }

    func testRejectsPathTraversalEvenWhenSkillIDIsAllowlisted() throws {
        let json = validProposal.replacingOccurrences(of: "workspace/hello.txt", with: "workspace/../secrets.txt")
        XCTAssertThrowsError(try PythonAgentPlanEnvelope.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? PythonAgentBridgeError, .invalidPlan)
        }
    }

    func testClarificationCannotCarryToolArguments() throws {
        let json = """
        {
          "schema_version": 1,
          "kind": "clarify",
          "intent": {"kind": "create_file", "normalized_text": "Tạo file"},
          "message": "Please provide the file path and content.",
          "missing_fields": ["path", "content"],
          "skill_id": null,
          "arguments": {"path": "workspace/hidden.txt", "content": "x"},
          "is_executable": false
        }
        """
        XCTAssertThrowsError(try PythonAgentPlanEnvelope.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? PythonAgentBridgeError, .invalidPlan)
        }
    }

    func testDecodesClarificationWithoutExecutionProposal() throws {
        let json = """
        {
          "schema_version": 1,
          "kind": "clarify",
          "intent": {"kind": "create_file", "normalized_text": "Tạo file"},
          "message": "Please provide the file path and content.",
          "missing_fields": ["path", "content"],
          "skill_id": null,
          "arguments": {},
          "is_executable": false
        }
        """
        let plan = try PythonAgentPlanEnvelope.decode(Data(json.utf8))
        XCTAssertEqual(plan.kind, .clarify)
        XCTAssertEqual(plan.missingFields, ["path", "content"])
        XCTAssertNil(plan.skillID)
        XCTAssertTrue(plan.arguments.isEmpty)
    }

    private var validProposal: String {
        """
        {
          "schema_version": 1,
          "kind": "propose_skill",
          "intent": {
            "kind": "create_file",
            "normalized_text": "Create file workspace/hello.txt with content: hello"
          },
          "message": "Proposal only",
          "missing_fields": [],
          "skill_id": "workspace.create-file",
          "arguments": {
            "path": "workspace/hello.txt",
            "content": "hello"
          },
          "is_executable": false
        }
        """
    }
}
