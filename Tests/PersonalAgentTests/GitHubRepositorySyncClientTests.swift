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

    func testPotentialSecretsBlockSyncBeforeAnyNetworkRequest() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("config"), withIntermediateDirectories: true)
        let fakeToken = "sk-" + String(repeating: "A", count: 20)
        try "{\"api_key\":\"\(fakeToken)\"}".write(
            to: workspace.appendingPathComponent("config/settings.json"),
            atomically: true,
            encoding: .utf8
        )
        let transport = RecordingGitHubTransport()
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: base.appendingPathComponent("state/state.json"),
            transport: transport,
            tokenProvider: { "test-token" }
        )
        do {
            _ = try await client.synchronize(workspaceURL: workspace)
            XCTFail("Secret-like content must fail closed before network access")
        } catch let error as GitHubRepositorySyncError {
            XCTAssertEqual(error, .potentialSecret("config/settings.json"))
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
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
