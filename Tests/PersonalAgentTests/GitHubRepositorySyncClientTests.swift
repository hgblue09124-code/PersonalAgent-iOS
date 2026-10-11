import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PAWorkspace

final class GitHubRepositorySyncClientTests: XCTestCase {
    func testRepositoryAndBranchValidationRejectTraversal() {
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "../main"))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: ".hidden"))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "feature//nested"))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "feature.lock"))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "feature."))
        XCTAssertThrowsError(try GitHubRepositoryLocation(owner: "owner", repository: "repo", branch: "../repo"))
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

    func testRemoteSecretBlocksSyncBeforeAnyWorkspaceMutation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let stateURL = base.appendingPathComponent("state/state.json")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let safeBytes = Data("safe remote skill content\n".utf8)
        let secretToken = "sk-" + String(repeating: "A", count: 20)
        let secretBytes = Data("{\"api_key\":\"\(secretToken)\"}\n".utf8)
        let safeSHA = GitBlobSHA1.hash(safeBytes)
        let secretSHA = GitBlobSHA1.hash(secretBytes)
        let remoteCommit = String(repeating: "b", count: 40)
        let treeSHA = String(repeating: "c", count: 40)
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": remoteCommit]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [
                ["path": "skills/a-safe.md", "mode": "100644", "type": "blob", "sha": safeSHA, "size": safeBytes.count],
                ["path": "skills/z-notes.md", "mode": "100644", "type": "blob", "sha": secretSHA, "size": secretBytes.count]
            ]]),
            Self.response(["sha": safeSHA, "encoding": "base64", "content": safeBytes.base64EncodedString()]),
            Self.response(["sha": secretSHA, "encoding": "base64", "content": secretBytes.base64EncodedString()])
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
            XCTFail("Remote secret-like content must fail closed before workspace mutation")
        } catch let error as GitHubRepositorySyncError {
            XCTAssertEqual(error, .potentialSecret("skills/z-notes.md"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/a-safe.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/z-notes.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 5)
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

    func testPreviewReportsPlannedChangesWithoutMutatingLocalRemoteOrBaseline() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let stateURL = base.appendingPathComponent("state/state.json")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("skills"), withIntermediateDirectories: true)
        let localFile = workspace.appendingPathComponent("skills/local.md")
        try Data("local draft\n".utf8).write(to: localFile)

        let remoteBytes = Data("remote skill\n".utf8)
        let remoteSHA = GitBlobSHA1.hash(remoteBytes)
        let remoteCommit = String(repeating: "b", count: 40)
        let treeSHA = String(repeating: "c", count: 40)
        let state: [String: Any] = [
            "repositoryKey": "example/agentos@main",
            "commitSHA": String(repeating: "a", count: 40),
            "files": [String: String]()
        ]
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let originalState = try Data(contentsOf: stateURL)
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": remoteCommit]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [[
                "path": "skills/remote.md", "mode": "100644", "type": "blob",
                "sha": remoteSHA, "size": remoteBytes.count
            ]]]),
            Self.response(["sha": remoteSHA, "encoding": "base64", "content": remoteBytes.base64EncodedString()])
        ])
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: stateURL,
            transport: transport,
            tokenProvider: { "test-token" }
        )

        let result = try await client.synchronize(workspaceURL: workspace, previewOnly: true)
        XCTAssertEqual(result.commitSHA, remoteCommit)
        XCTAssertEqual(result.uploadedPaths, ["skills/local.md"])
        XCTAssertEqual(result.downloadedPaths, ["skills/remote.md"])
        XCTAssertEqual(result.deletedPaths, [])
        XCTAssertFalse(result.unchanged)

        XCTAssertEqual(try String(contentsOf: localFile, encoding: .utf8), "local draft\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/remote.md").path))
        XCTAssertEqual(try Data(contentsOf: stateURL), originalState)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testApplyFailureRollsBackEarlierLocalDownloadsAndPreservesBaseline() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let stateURL = base.appendingPathComponent("state/state.json")
        defer { try? FileManager.default.removeItem(at: base) }
        let skills = workspace.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)

        let originalBytes = Data("keep executable file\n".utf8)
        let originalFile = skills.appendingPathComponent("a.md")
        try originalBytes.write(to: originalFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: originalFile.path)
        let originalSHA = GitBlobSHA1.hash(originalBytes)
        let obstruction = skills.appendingPathComponent("z")
        try Data("keep obstruction".utf8).write(to: obstruction)

        let nestedBytes = Data("nested remote file\n".utf8)
        let nestedSHA = GitBlobSHA1.hash(nestedBytes)
        let remoteCommit = String(repeating: "b", count: 40)
        let treeSHA = String(repeating: "c", count: 40)
        let state: [String: Any] = [
            "repositoryKey": "example/agentos@main",
            "commitSHA": String(repeating: "a", count: 40),
            "files": ["skills/a.md": originalSHA]
        ]
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let originalState = try Data(contentsOf: stateURL)
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": remoteCommit]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [[
                "path": "skills/z/nested.md", "mode": "100644", "type": "blob",
                "sha": nestedSHA, "size": nestedBytes.count
            ]]]),
            Self.response(["sha": nestedSHA, "encoding": "base64", "content": nestedBytes.base64EncodedString()])
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
            XCTFail("A file-vs-directory obstruction must fail the local apply phase")
        } catch is GitHubRepositorySyncError {
            XCTFail("Rollback should preserve the original filesystem error when rollback succeeds")
        } catch {
            // Expected: creating skills/z as a directory fails because it is a regular file.
        }

        XCTAssertEqual(try String(contentsOf: originalFile, encoding: .utf8), "keep executable file\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: originalFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertNotEqual(permissions & 0o111, 0, "Rollback must preserve executable permissions")
        XCTAssertEqual(try String(contentsOf: obstruction, encoding: .utf8), "keep obstruction")
        XCTAssertEqual(try Data(contentsOf: stateURL), originalState)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
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
            XCTAssertEqual(error, .remoteConflict(paths: ["skills/demo.md"]))
            XCTAssertTrue(error.localizedDescription.contains("skills/demo.md"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "local edit\n")
    }

    func testDownloadsRemoteOnlyTextFileAndPersistsBaseline() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let remoteBytes = Data("remote skill content\\n".utf8)
        let blobSHA = GitBlobSHA1.hash(remoteBytes)
        let remoteCommit = String(repeating: "b", count: 40)
        let treeSHA = String(repeating: "c", count: 40)
        let stateURL = base.appendingPathComponent("state/state.json")
        let transport = ScriptedGitHubTransport(responses: [
            Self.response(["object": ["sha": remoteCommit]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [[
                "path": "skills/remote.md", "mode": "100755", "type": "blob",
                "sha": blobSHA, "size": remoteBytes.count
            ]]]),
            Self.response(["sha": blobSHA, "encoding": "base64", "content": remoteBytes.base64EncodedString()])
        ])
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try GitHubRepositorySyncClient(
            location: location,
            stateURL: stateURL,
            transport: transport,
            tokenProvider: { "test-token" }
        )

        let result = try await client.synchronize(workspaceURL: workspace)
        XCTAssertEqual(result.commitSHA, remoteCommit)
        XCTAssertEqual(result.downloadedPaths, ["skills/remote.md"])
        XCTAssertTrue(result.uploadedPaths.isEmpty)
        let downloadedFile = workspace.appendingPathComponent("skills/remote.md")
        XCTAssertEqual(try Data(contentsOf: downloadedFile), remoteBytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: downloadedFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertNotEqual(permissions & 0o111, 0, "Remote executable mode must be preserved")

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "GET", "GET", "GET"])
        let persisted = try Data(contentsOf: stateURL)
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        let files = try XCTUnwrap(state["files"] as? [String: String])
        XCTAssertEqual(files["skills/remote.md"], blobSHA)
    }

    private static func response(_ object: Any) -> GitHubSyncHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return GitHubSyncHTTPResponse(statusCode: 200, data: data)
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
    func testSymlinkDirectoryFailsClosedBeforeRemoteDownload() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("workspace")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: workspace.appendingPathComponent("skills").path,
            withDestinationPath: outside.path
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
            XCTFail("Symlink directories must not redirect remote writes outside the workspace")
        } catch let error as GitHubRepositorySyncError {
            XCTAssertEqual(error, .unsafePath("skills"))
        }

        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty, "Unsafe local symlinks must be rejected before network access")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("remote.md").path))
    }

    func testBareProviderSpecificTokensBlockSyncBeforeNetworkAccess() async throws {
        let fakeTokens = [
            "xoxb-" + String(repeating: "A", count: 24),
            "AIza" + String(repeating: "A", count: 35),
            "hf_" + String(repeating: "A", count: 32),
            "AKIA" + String(repeating: "A", count: 16)
        ]

        for (index, token) in fakeTokens.enumerated() {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let workspace = base.appendingPathComponent("workspace")
            let skillDirectory = workspace.appendingPathComponent("skills")
            try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
            try token.write(to: skillDirectory.appendingPathComponent("token\(index).md"), atomically: true, encoding: .utf8)

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
                XCTFail("Bare provider-specific token patterns must fail closed")
            } catch let error as GitHubRepositorySyncError {
                XCTAssertEqual(error, .potentialSecret("skills/token\(index).md"))
            }
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

}
