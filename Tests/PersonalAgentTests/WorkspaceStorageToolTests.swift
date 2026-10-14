import Foundation
import XCTest
import PAKernel
import PAWorkspace
import PAModules
import PASkills
@testable import PAComposition

final class WorkspaceStorageToolTests: XCTestCase {
    func testAgentStorageWriteReadAndMkdirAreVerified() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()

        let writer = WorkspaceWriteTool(workspace: workspace)
        let reader = WorkspaceReadTool(workspace: workspace)
        _ = try await writer.run(argumentsJSON: #"{"operation":"mkdir","path":"workspace/notes"}"#)
        _ = try await writer.run(argumentsJSON: #"{"operation":"write","path":"workspace/notes/plan.md","content":"Verified plan"}"#)

        let result = try await reader.run(argumentsJSON: #"{"operation":"read","path":"workspace/notes/plan.md"}"#)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, "Verified plan")
        XCTAssertEqual(object["verified"] as? Bool, true)
    }

    func testReadToolRejectsPathTraversal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let reader = WorkspaceReadTool(workspace: workspace)

        do {
            _ = try await reader.run(argumentsJSON: #"{"operation":"read","path":"../private.txt"}"#)
            XCTFail("Path traversal must be rejected")
        } catch {
            // Fail-closed is the expected contract.
        }
    }

    func testReadToolRejectsProtectedParentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let secretDirectory = root.appendingPathComponent("workspace/secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: secretDirectory, withIntermediateDirectories: true)
        try "private".write(
            to: secretDirectory.appendingPathComponent("note.md"),
            atomically: true,
            encoding: .utf8
        )
        let reader = WorkspaceReadTool(workspace: workspace)

        do {
            _ = try await reader.run(argumentsJSON: #"{"operation":"read","path":"workspace/secrets/note.md"}"#)
            XCTFail("Protected parent directories must be rejected")
        } catch {
            // Fail-closed is the expected contract.
        }
    }

    func testReadToolRejectsSymlinkEscapingWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }

        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try "external private content".write(
            to: external.appendingPathComponent("private.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("workspace/linked.md"),
            withDestinationURL: external.appendingPathComponent("private.md")
        )

        let reader = WorkspaceReadTool(workspace: workspace)
        do {
            _ = try await reader.run(argumentsJSON: #"{"operation":"read","path":"workspace/linked.md"}"#)
            XCTFail("Reading a symlink outside the workspace must be rejected")
        } catch {
            // Fail-closed is the expected contract.
        }
    }

    func testSearchSkipsProtectedSymlinkDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }

        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try "needle".write(to: external.appendingPathComponent("private.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("workspace/secrets", isDirectory: true),
            withDestinationURL: external
        )

        let reader = WorkspaceReadTool(workspace: workspace)
        let result = try await reader.run(argumentsJSON: #"{"operation":"search","query":"needle"}"#)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["matches"] as? [String], [])
    }

    func testWriteToolRejectsSecretLikeContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let writer = WorkspaceWriteTool(workspace: workspace)

        do {
            let fakeSecret = "api_key = \"sk-" + String(repeating: "A", count: 24) + "\""
            let payload: [String: String] = [
                "operation": "write",
                "path": "workspace/notes.md",
                "content": fakeSecret,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let arguments = try XCTUnwrap(String(data: data, encoding: .utf8))
            _ = try await writer.run(argumentsJSON: arguments)
            XCTFail("Secret-like content must be rejected")
        } catch {
            // Fail-closed is the expected contract.
        }
        let exists = try await workspace.exists(at: "workspace/notes.md")
        XCTAssertFalse(exists)
    }

    func testChatSkillCreatesAndReadBackVerifiesWorkspaceFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()

        let catalog = try ModuleCatalog(modules: [
            ToolModule(tool: WorkspaceReadTool(workspace: workspace)),
            ToolModule(tool: WorkspaceWriteTool(workspace: workspace))
        ])
        let policy = AllowWorkspaceToolPolicy()
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read, .write, .execute],
            policy: policy
        )
        let skillStore = FileSkillStore(directoryURL: root.appendingPathComponent("Skills", isDirectory: true))
        try await skillStore.ensureDefaultSkill()
        let runtime = SkillRuntime(store: skillStore, moduleRuntime: moduleRuntime)
        let agentStore = FileAgentStore(directoryURL: root.appendingPathComponent("Agents", isDirectory: true))
        try await agentStore.ensureDefaultAgent()
        let agent = try await agentStore.load(id: "personal.default")
        let orchestrator = SkillAgentOrchestrator(runtime: runtime)

        let output = try await orchestrator.run(
            agent: agent,
            goalStatement: "Tạo file workspace/notes.md với nội dung: Nội dung đã ghi thật",
            inputJSON: try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: ["text": SkillRuntime.chatInputText(from: "Tạo file workspace/notes.md với nội dung: Nội dung đã ghi thật")], options: [.sortedKeys]), encoding: .utf8)),
            policy: policy
        )

        XCTAssertTrue(output.verified)
        XCTAssertTrue(output.outputJSON.contains("verified"))
        let vietnameseFile = try await workspace.readFile(at: "workspace/notes.md")
        XCTAssertEqual(vietnameseFile, "Nội dung đã ghi thật")

        let englishOutput = try await orchestrator.run(
            agent: agent,
            goalStatement: "Create file workspace/english.md with content: English file",
            inputJSON: try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: ["text": SkillRuntime.chatInputText(from: "Create file workspace/english.md with content: English file")], options: [.sortedKeys]), encoding: .utf8)),
            policy: policy
        )
        XCTAssertTrue(englishOutput.verified)
        XCTAssertTrue(englishOutput.outputJSON.contains("verified"))
        let englishFile = try await workspace.readFile(at: "workspace/english.md")
        XCTAssertEqual(englishFile, "English file")
    }

    func testDefaultAgentMigrationAddsFileSkillWithoutReplacingCustomizedAgent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let legacy = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent.
        ---
        ## Skills
        text.normalize

        ## Rule
        Select only from the declared skills.
        """
        try legacy.write(to: agents.appendingPathComponent("personal.default.Agent.md"), atomically: true, encoding: .utf8)
        let store = FileAgentStore(directoryURL: agents)
        try await store.ensureDefaultAgent()
        let migrated = try await store.load(id: "personal.default")
        XCTAssertTrue(migrated.skillIDs.contains(SkillID(rawValue: "workspace.create-file")))

        let customRoot = root.appendingPathComponent("CustomAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: customRoot, withIntermediateDirectories: true)
        let custom = legacy + "\n# user customization"
        try custom.write(to: customRoot.appendingPathComponent("personal.default.Agent.md"), atomically: true, encoding: .utf8)
        let customStore = FileAgentStore(directoryURL: customRoot)
        try await customStore.ensureDefaultAgent()
        XCTAssertEqual(try String(contentsOf: customRoot.appendingPathComponent("personal.default.Agent.md"), encoding: .utf8), custom)
    }

    func testWorkspaceRejectsRepositoryMetadataAndCredentialDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()

        for path in [".git/hooks/pre-commit", ".ssh/id_ed25519", ".aws/credentials"] {
            do {
                try await workspace.writeFile("untrusted", to: path)
                XCTFail("Protected system path must be rejected: \(path)")
            } catch {
                // Expected: direct AgentWorkspace calls must enforce the boundary.
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
    }

}


private struct AllowWorkspaceToolPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        .allow("workspace execution test")
    }
}
