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

    func testDirectWorkspaceAccessBlocksProtectedPathsAndHidesNames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let secretURL = root.appendingPathComponent("config/api_key.json")
        try Data("protected fixture".utf8).write(to: secretURL)
        try await workspace.writeFile("safe settings", to: "config/settings.md")

        do {
            _ = try await workspace.readFile(at: "config/api_key.json")
            XCTFail("direct reads of protected paths must fail")
        } catch { }
        do {
            try await workspace.writeFile("replacement", to: "config/api_key.json")
            XCTFail("direct writes to protected paths must fail")
        } catch { }
        do {
            try await workspace.remove(at: "config/api_key.json")
            XCTFail("direct deletes of protected paths must fail")
        } catch { }

        let entries = try await workspace.listDirectory(at: "config")
        XCTAssertFalse(entries.contains { $0.relativePath == "config/api_key.json" })
        let safeRead = try await workspace.readFile(at: "config/settings.md")
        XCTAssertEqual(safeRead, "safe settings")
    }

    func testDirectWorkspaceAccessBlocksSecretLikeContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = LocalAgentWorkspace(rootURL: root)
        try await workspace.prepare()
        let sample = "api_key = \"sk-" + String(repeating: "A", count: 24) + "\""

        do {
            try await workspace.writeFile(sample, to: "workspace/new-note.md")
            XCTFail("secret-like content must not be written")
        } catch let error as AgentWorkspaceError {
            XCTAssertEqual(error, .protectedContent)
        }

        let externalFile = root.appendingPathComponent("workspace/external-note.md")
        try sample.write(to: externalFile, atomically: true, encoding: .utf8)
        do {
            _ = try await workspace.readFile(at: "workspace/external-note.md")
            XCTFail("secret-like content must not be read through the workspace")
        } catch let error as AgentWorkspaceError {
            XCTAssertEqual(error, .protectedContent)
        }

        try await workspace.writeFile("safe", to: "workspace/append-note.md")
        do {
            try await workspace.appendFile(sample, to: "workspace/append-note.md")
            XCTFail("secret-like content must not be appended")
        } catch let error as AgentWorkspaceError {
            XCTAssertEqual(error, .protectedContent)
        }
        let safeValue = try await workspace.readFile(at: "workspace/append-note.md")
        XCTAssertEqual(safeValue, "safe")
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
