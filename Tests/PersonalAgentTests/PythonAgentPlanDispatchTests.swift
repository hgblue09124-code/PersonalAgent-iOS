import Foundation
import Testing
import PAKernel
import PASkills
@testable import PAComposition

@Suite("Python Agent Plan Dispatch")
struct PythonAgentPlanDispatchTests {
    private struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .allow("test policy; production policy remains authoritative")
        }
    }

    @Test("A Python create-file proposal uses canonical policy and verified Skill execution")
    func proposalCreatesAndReadsBackExactFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let content = "  func greet() {\n\n    print(\"hello\")\n  }"
        let result = try await root.dispatchPythonAgentPlan(
            proposal(path: "workspace/bridge.swift", content: content)
        )

        switch result {
        case .verified(let skillResult):
            #expect(skillResult.skillID.rawValue == "workspace.create-file")
            #expect(skillResult.verified)
            let fileURL = directory.appendingPathComponent("workspace/bridge.swift")
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)
        default:
            Issue.record("Expected a verified Skill result, got: \(result)")
        }
    }

    @Test("Workspace-disabled configuration fails closed for a Python proposal")
    func disabledWorkspaceDoesNotWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )
        let result = try await root.dispatchPythonAgentPlan(
            proposal(path: "workspace/blocked.txt", content: "must not be written")
        )

        switch result {
        case .executionFailed:
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/blocked.txt").path))
        default:
            Issue.record("Expected fail-closed result, got: \(result)")
        }
    }

    @Test("Clarification and conversational plans never enter Skill execution")
    func nonActionablePlansStayOutOfExecution() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )

        let clarification = try await root.dispatchPythonAgentPlan(
            plan(kind: "clarify", intent: "create_file", message: "Please provide a path and content.", missing: ["path", "content"])
        )
        let conversation = try await root.dispatchPythonAgentPlan(
            plan(kind: "respond", intent: "chat", message: "No action proposed.")
        )
        #expect(clarification == .clarification("Please provide a path and content."))
        #expect(conversation == .notActionable("No action proposed."))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/bridge.txt").path))
    }

    @Test("Invalid Python payload is rejected before routing")
    func invalidProposalCannotReachWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let invalid = proposal(path: "workspace/../outside.txt", content: "no")
        do {
            _ = try await root.dispatchPythonAgentPlan(invalid)
            Issue.record("Expected invalid Python plan to be rejected")
        } catch {
            #expect(error as? PythonAgentBridgeError == .invalidPlan)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("outside.txt").path))
    }

    private func proposal(path: String, content: String) throws -> Data {
        try plan(
            kind: "propose_skill",
            intent: "create_file",
            message: "Proposal only.",
            skillID: "workspace.create-file",
            arguments: ["path": path, "content": content]
        )
    }

    private func plan(
        kind: String,
        intent: String,
        message: String,
        missing: [String] = [],
        skillID: String? = nil,
        arguments: [String: String] = [:]
    ) throws -> Data {
        let skillValue: Any = skillID.map { $0 as Any } ?? NSNull()
        let object: [String: Any] = [
            "schema_version": 1,
            "kind": kind,
            "intent": ["kind": intent, "normalized_text": message],
            "message": message,
            "missing_fields": missing,
            "skill_id": skillValue,
            "arguments": arguments,
            "is_executable": false
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
