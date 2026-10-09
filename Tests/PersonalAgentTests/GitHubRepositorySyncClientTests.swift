import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PAWorkspace

final class GitHubRepositorySyncClientTests: XCTestCase {
    func testRepositoryAndBranchValidationRejectTraversal() {
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "../main"))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "../repo"))
        XCTAssertTrue(GitHubRepositorySyncClient.isSafePath("skills/Memory.md"))
        XCTAssertFalse(GitHubRepositorySyncClient.isSafePath("../outside.md"))
        XCTAssertFalse(GitHubRepositorySyncClient.isSafePath(".git/config"))
        XCTAssertFalse(GitHubRepositorySyncClient.isSyncablePath("config/api_keys.json"))
        XCTAssertFalse(GitHubRepositorySyncClient.isSyncablePath("models/model.gguf"))
        XCTAssertFalse(GitHubRepositorySyncClient.isSyncablePath("assets/screenshot.png"))
        XCTAssertTrue(GitHubRepositorySyncClient.isSyncablePath("skills/Memory.md"))
        XCTAssertTrue(GitHubRepositorySyncClient.shouldDescendDirectory("agents"))
        XCTAssertTrue(GitHubRepositorySyncClient.shouldDescendDirectory("skills"))
        XCTAssertFalse(GitHubRepositorySyncClient.shouldDescendDirectory("memory"))
    }

    func testGitBlobSHA1MatchesGitKnownVector() {
        XCTAssertEqual(GitBlobSHA1.hash(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testUploadsLocalTextAndUpdatesBranchWithoutForce() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("skills"), withIntermediateDirectories: true)
        let file = workspace.appendingPathComponent("skills/demo.md")
        let bytes = Data("skill content\n".utf8)
        try bytes.write(to: file)

        let commitSHA = String(repeating: "1", count: 40)
        let treeSHA = String(repeating: "2", count: 40)
        let newTreeSHA = String(repeating: "3", count: 40)
        let newCommitSHA = String(repeating: "4", count: 40)
        let blobSHA = GitBlobSHA1.hash(bytes)
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": commitSHA]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": []]),
            Self.response(["sha": blobSHA]),
            Self.response(["sha": newTreeSHA]),
            Self.response(["sha": newCommitSHA]),
            Self.response(["object": ["sha": newCommitSHA]])
        ])
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: base.appendingPathComponent("state/state.json"),
            transport: transport,
            tokenProvider: { "test-token" }
        )

        let result = try await client.synchronize(workspaceURL: workspace)
        XCTAssertEqual(result.commitSHA, newCommitSHA)
        XCTAssertEqual(result.uploadedPaths, ["skills/demo.md"])
        XCTAssertTrue(result.downloadedPaths.isEmpty)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "GET", "GET", "POST", "POST", "POST", "PATCH"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
        let patchBody = try XCTUnwrap(requests.last?.httpBody)
        let patchJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: patchBody) as? [String: Any])
        XCTAssertEqual(patchJSON["force"] as? Bool, false)
    }

    func testDivergentLocalAndRemoteEditsFailBeforeWritingRemote() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("skills"), withIntermediateDirectories: true)
        let file = workspace.appendingPathComponent("skills/demo.md")
        let localBytes = Data("local edit\n".utf8)
        let remoteBytes = Data("remote edit\n".utf8)
        try localBytes.write(to: file)

        let baseSHA = GitBlobSHA1.hash(Data("base version\n".utf8))
        let remoteSHA = GitBlobSHA1.hash(remoteBytes)
        let remoteCommit = String(repeating: "b", count: 40)
        let treeSHA = String(repeating: "c", count: 40)
        let state: [String: Any] = [
            "repositoryKey": "example/agentos@main",
            "commitSHA": String(repeating: "a", count: 40),
            "files": ["skills/demo.md": baseSHA]
        ]
        let stateURL = base.appendingPathComponent("state/state.json")
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": remoteCommit]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [[
                "path": "skills/demo.md", "mode": "100644", "type": "blob",
                "sha": remoteSHA, "size": remoteBytes.count
            ]]])
        ])
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: stateURL,
            transport: transport,
            tokenProvider: { "test-token" }
        )

        do {
            _ = try await client.synchronize(workspaceURL: workspace)
            XCTFail("Divergent edits must stop as a conflict")
        } catch let error as GitHubRepositorySyncError {
            XCTAssertEqual(error, .remoteConflict)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "local edit\n")
    }

    private static func response(_ object: [String: Any]) -> GitHubSyncHTTPResponse {
        GitHubSyncHTTPResponse(
            statusCode: 200,
            data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        )
    }

    func testMissingCredentialFailsBeforeNetworkAccess() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let transport = RecordingGitHubTransport()
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: base.appendingPathComponent("state.json"),
            transport: transport,
            tokenProvider: { nil }
        )
        do {
            _ = try await client.synchronize(workspaceURL: workspace)
            XCTFail("Sync must fail closed without a token")
        } catch let error as GitHubRepositorySyncError {
            XCTAssertEqual(error, .authenticationRequired)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

private actor RecordingGitHubTransport: GitHubSyncHTTPTransport {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> GitHubSyncHTTPResponse {
        requests.append(request)
        return GitHubSyncHTTPResponse(statusCode: 500, data: Data())
    }
}

private actor ScriptedGitHubTransport: GitHubSyncHTTPTransport {
    private var responses: [GitHubSyncHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [GitHubSyncHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> GitHubSyncHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            return GitHubSyncHTTPResponse(statusCode: 500, data: Data())
        }
        return responses.removeFirst()
    }
}
