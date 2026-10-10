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
}
