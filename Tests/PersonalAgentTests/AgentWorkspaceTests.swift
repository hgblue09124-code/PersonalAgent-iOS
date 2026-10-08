import XCTest
@testable import PAWorkspace

final class AgentWorkspaceTests: XCTestCase {
    func testRejectsTraversalAndAbsolutePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        do { _ = try await workspace.readFile(at: "../escape") ; XCTFail("traversal must fail") } catch { }
        do { _ = try await workspace.readFile(at: "/private/escape") ; XCTFail("absolute path must fail") } catch { }
    }

    func testRejectsDotPathsAndProtectsWorkspaceRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()

        for path in [".", "./file", "a/./file", "..", "a/../file"] {
            do {
                _ = try await workspace.exists(at: path)
                XCTFail("unsafe path must fail: \(path)")
            } catch {
                // Expected.
            }
        }

        do {
            try await workspace.remove(at: ".")
            XCTFail("workspace root must never be removable")
        } catch {
            // Expected.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(try await workspace.exists(at: "workspace"))
    }

    func testUnicodeWriteReadExistsMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let path = "workspace/tiếng Việt-😀.md"
        let value = "AgentOS ✓"
        try await workspace.writeFile(value, to: path)
        XCTAssertTrue(try await workspace.exists(at: path))
        XCTAssertEqual(try await workspace.readFile(at: path), value)
        XCTAssertEqual(try await workspace.metadata(at: path).byteCount, value.utf8.count)
    }

    func testPreparedDirectoriesExist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        for directory in ["agents", "skills", "modules", "tools", "workspace", "memory", "config", "logs", "cache"] {
            XCTAssertTrue(try await workspace.exists(at: directory))
        }
    }
}
