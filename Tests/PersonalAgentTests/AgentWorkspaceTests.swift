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
        try await workspace.writeFile("safe", to: "workspace/safe.txt")
        for path in [".", "./workspace/safe.txt", "workspace/./safe.txt"] {
            do { try await workspace.remove(at: path); XCTFail("dot path must fail: " + path) } catch { }
        }
        let safeExists = try await workspace.exists(at: "workspace/safe.txt")
        XCTAssertTrue(safeExists)
        do { _ = try await workspace.exists(at: "."); XCTFail("dot root path must fail") } catch { }
    }

    func testWorkspacePathNormalizesWindowsSeparatorsBeforeTraversalValidation() throws {
        let normalized = try WorkspacePath("workspace\\notes.md")
        XCTAssertEqual(normalized.value, "workspace/notes.md")

        XCTAssertThrowsError(try WorkspacePath("workspace\\..\\outside.txt"))
        XCTAssertThrowsError(try WorkspacePath("workspace\\.\\notes.md"))
    }

    func testUnicodeWriteReadExistsMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let path = "workspace/tiếng Việt-😀.md"
        let value = "AgentOS ✓"
        try await workspace.writeFile(value, to: path)
        let exists = try await workspace.exists(at: path)
        XCTAssertTrue(exists)
        let read = try await workspace.readFile(at: path)
        XCTAssertEqual(read, value)
        let metadata = try await workspace.metadata(at: path)
        XCTAssertEqual(metadata.byteCount, value.utf8.count)
    }

    func testPreparedDirectoriesExist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        for directory in ["agents", "skills", "modules", "tools", "workspace", "memory", "config", "logs", "cache"] {
            let exists = try await workspace.exists(at: directory)
            XCTAssertTrue(exists)
        }
    }
}


final class WorkspaceContentSafetyTests: XCTestCase {
    func testProtectedPathPolicyIsCaseInsensitiveAndChecksEveryComponent() {
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("workspace/secrets.md"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("skills/Private-Token.md"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("workspace/.ENV"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("workspace/.env.production"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config/.env.staging.local"))
        XCTAssertFalse(WorkspaceContentSafety.isProtectedPath("workspace/notes.md"))
    }

    func testProtectedPathPolicyNormalizesWindowsSeparators() {
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("workspace\\secrets.md"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config\\private-token.json"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config/api_key.json"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config/private_key.json"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config/access-key.json"))
        XCTAssertTrue(WorkspaceContentSafety.isProtectedPath("config/passwords.txt"))
        XCTAssertFalse(WorkspaceContentSafety.isProtectedPath("workspace\\notes.md"))
    }

    func testSharedSecretPolicyRecognizesCommonProviderAndCloudTokens() {
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret("OPENROUTER_API_KEY = \"or-v1-1234567890abcdefghijklmnop\""))
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret("or-v1-1234567890abcdefghijklmnop"))
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret("xoxb-12345678901234567890"))
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret("AKIA1234567890ABCDEF"))
        XCTAssertFalse(WorkspaceContentSafety.containsPotentialSecret("A note explaining why API keys should be stored safely."))
    }

    func testSecretLikeContentIsRejectedWithoutEchoingTheSecret() {
        let sample = "api_key = \"sk-" + "1234567890abcdefghijklmnop\""
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret(sample))
        XCTAssertTrue(WorkspaceContentSafety.containsPotentialSecret("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"))
        XCTAssertFalse(WorkspaceContentSafety.containsPotentialSecret("This is an ordinary note about API design."))
    }
}
