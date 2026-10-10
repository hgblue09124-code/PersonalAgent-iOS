import Foundation
import XCTest
import PAWorkspace
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

    func testWriteToolRejectsSecretLikeContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let writer = WorkspaceWriteTool(workspace: workspace)

        do {
            _ = try await writer.run(
                argumentsJSON: #"{"operation":"write","path":"workspace/notes.md","content":"api_key = \"sk-12345678901234567890\""}"#
            )
            XCTFail("Secret-like content must be rejected")
        } catch {
            // Fail-closed is the expected contract.
        }
        let exists = try await workspace.exists(at: "workspace/notes.md")
        XCTAssertFalse(exists)
    }
}
