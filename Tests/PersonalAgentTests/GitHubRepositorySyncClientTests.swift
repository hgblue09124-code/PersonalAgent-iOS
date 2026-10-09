import XCTest
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
    }

    func testGitBlobSHA1MatchesGitKnownVector() {
        XCTAssertEqual(GitBlobSHA1.hash(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testMissingCredentialFailsBeforeNetworkAccess() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let transport = RecordingGitHubTransport()
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: base.appendingPathComponent("state.json"),
            transport: transport,
            tokenProvider: { nil }
        )
        do {
            _ = try await client.synchronize(workspaceURL: base)
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
