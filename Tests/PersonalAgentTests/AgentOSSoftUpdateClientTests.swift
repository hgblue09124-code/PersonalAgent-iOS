import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PAWorkspace
import PAComposition

final class AgentOSSoftUpdateClientTests: XCTestCase {
    func testSHA256MatchesKnownVector() {
        XCTAssertEqual(AgentOSSoftUpdateClient.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAllowedPathsAreNarrowAndRejectTraversalOrExecutableCode() {
        XCTAssertTrue(AgentOSSoftUpdateClient.isAllowedPath("skills/demo/SKILL.md"))
        XCTAssertTrue(AgentOSSoftUpdateClient.isAllowedPath("agents/Agent.json"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("../skills/evil.md"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("/skills/evil.md"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("skills/../../evil.md"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("skills/run.swift"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("memory/private.md"))
        XCTAssertFalse(AgentOSSoftUpdateClient.isAllowedPath("skills\\evil.md"))
    }

    func testManifestRoundTripsFileBaseHashForConflictDetection() throws {
        let file = AgentOSSoftUpdateManifest.File(
            path: "skills/demo/SKILL.md",
            sha256: String(repeating: "a", count: 64),
            byteCount: 12,
            baseSHA256: "missing"
        )
        let manifest = AgentOSSoftUpdateManifest(
            repository: "owner/repo",
            baseRevision: "abc123",
            version: "2",
            revision: "def456",
            compatibility: "runtime-v1",
            files: [file]
        )
        let decoded = try JSONDecoder().decode(
            AgentOSSoftUpdateManifest.self,
            from: JSONEncoder().encode(manifest)
        )
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.files.first?.baseSHA256, "missing")
    }
    func testStageFetchesVerifiedContentWithoutChangingWorkspace() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let staging = base.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let content = Data("id: text.normalize\n".utf8)
        let manifest = AgentOSSoftUpdateManifest(repository: "example/agentos", baseRevision: "initial",
            version: "1", revision: "r1", compatibility: "runtime-v1",
            files: [.init(path: "skills/demo.Skill.md", sha256: AgentOSSoftUpdateClient.sha256Hex(content),
                          byteCount: Int64(content.count), baseSHA256: "missing")])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestSHA = GitBlobSHA1.hash(manifestData)
        let fileSHA = GitBlobSHA1.hash(content)
        let commitSHA = String(repeating: "a", count: 40)
        let treeSHA = String(repeating: "b", count: 40)
        let transport = ScriptedSoftUpdateTransport(responses: [
            Self.response(["object": ["sha": commitSHA]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [
                ["path": "agentos-update.json", "type": "blob", "sha": manifestSHA, "size": manifestData.count],
                ["path": "skills/demo.Skill.md", "type": "blob", "sha": fileSHA, "size": content.count]
            ]]),
            Self.response(["sha": manifestSHA, "encoding": "base64", "content": manifestData.base64EncodedString()]),
            Self.response(["sha": fileSHA, "encoding": "base64", "content": content.base64EncodedString()])
        ])
        let location = try GitHubRepositoryLocation(owner: "example", repository: "agentos")
        let client = try AgentOSSoftUpdateClient(location: location, transport: transport, tokenProvider: { "test-token" })
        let result = try await client.stageUpdate(currentRevision: "initial", runtimeCompatibility: "runtime-v1",
            workspaceURL: workspace, stagingRootURL: staging)
        XCTAssertEqual(result.manifest.revision, "r1")
        XCTAssertEqual(try Data(contentsOf: result.stagingURL.appendingPathComponent("skills/demo.Skill.md")), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/demo.Skill.md").path))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testLocalBaseHashConflictStopsBeforeFetchingTargetBlob() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("skills"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let local = Data("user edit".utf8)
        try local.write(to: workspace.appendingPathComponent("skills/demo.Skill.md"))
        let remote = Data("remote content".utf8)
        let manifest = AgentOSSoftUpdateManifest(repository: "example/agentos", baseRevision: "initial",
            version: "1", revision: "r1", compatibility: "runtime-v1",
            files: [.init(path: "skills/demo.Skill.md", sha256: AgentOSSoftUpdateClient.sha256Hex(remote),
                          byteCount: Int64(remote.count), baseSHA256: "missing")])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestSHA = GitBlobSHA1.hash(manifestData)
        let commitSHA = String(repeating: "a", count: 40)
        let treeSHA = String(repeating: "b", count: 40)
        let transport = ScriptedSoftUpdateTransport(responses: [
            Self.response(["object": ["sha": commitSHA]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [
                ["path": "agentos-update.json", "type": "blob", "sha": manifestSHA, "size": manifestData.count],
                ["path": "skills/demo.Skill.md", "type": "blob", "sha": GitBlobSHA1.hash(remote), "size": remote.count]
            ]]),
            Self.response(["sha": manifestSHA, "encoding": "base64", "content": manifestData.base64EncodedString()])
        ])
        let client = try AgentOSSoftUpdateClient(location: GitHubRepositoryLocation(owner: "example", repository: "agentos"),
            transport: transport, tokenProvider: { "test-token" })
        do {
            _ = try await client.stageUpdate(currentRevision: "initial", runtimeCompatibility: "runtime-v1",
                workspaceURL: workspace, stagingRootURL: base.appendingPathComponent("staging"))
            XCTFail("Local edit must block update")
        } catch let error as AgentOSSoftUpdateError {
            XCTAssertEqual(error, .localConflict("skills/demo.Skill.md"))
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(try Data(contentsOf: workspace.appendingPathComponent("skills/demo.Skill.md")), local)
    }

    private static func response(_ object: Any) -> GitHubSyncHTTPResponse {
        GitHubSyncHTTPResponse(statusCode: 200, data: try! JSONSerialization.data(withJSONObject: object))
    }


    func testCaseInsensitivePathCollisionsAreRejected() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let content = Data("same".utf8)
        let manifest = AgentOSSoftUpdateManifest(repository: "example/agentos", baseRevision: "initial",
            version: "1", revision: "r1", compatibility: "runtime-v1",
            files: [
                .init(path: "skills/Demo.md", sha256: AgentOSSoftUpdateClient.sha256Hex(content),
                      byteCount: Int64(content.count), baseSHA256: "missing"),
                .init(path: "skills/demo.md", sha256: AgentOSSoftUpdateClient.sha256Hex(content),
                      byteCount: Int64(content.count), baseSHA256: "missing")
            ])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestSHA = GitBlobSHA1.hash(manifestData)
        let commitSHA = String(repeating: "a", count: 40)
        let treeSHA = String(repeating: "b", count: 40)
        let transport = ScriptedSoftUpdateTransport(responses: [
            Self.response(["object": ["sha": commitSHA]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [
                ["path": "agentos-update.json", "type": "blob", "sha": manifestSHA, "size": manifestData.count],
                ["path": "skills/Demo.md", "type": "blob", "sha": GitBlobSHA1.hash(content), "size": content.count],
                ["path": "skills/demo.md", "type": "blob", "sha": GitBlobSHA1.hash(content), "size": content.count]
            ]]),
            Self.response(["sha": manifestSHA, "encoding": "base64", "content": manifestData.base64EncodedString()])
        ])
        let client = try AgentOSSoftUpdateClient(location: GitHubRepositoryLocation(owner: "example", repository: "agentos"),
            transport: transport, tokenProvider: { "test-token" })
        do {
            _ = try await client.stageUpdate(currentRevision: "initial", runtimeCompatibility: "runtime-v1",
                workspaceURL: workspace, stagingRootURL: base.appendingPathComponent("staging"))
            XCTFail("Case-colliding paths must fail closed")
        } catch let error as AgentOSSoftUpdateError {
            XCTAssertEqual(error, .duplicatePath("skills/demo.md"))
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
    }


    func testDefinitionValidatorRejectsDuplicateSkillAndAgentIDs() throws {
        let skill = """
        id: text.normalize
        name: Text Normalize
        version: 1.0.0
        executor: text.normalize
        ---
        ## Input
        input

        ## Output
        output

        ## Rule
        Trim surrounding whitespace.
        """
        XCTAssertThrowsError(try AgentOSSoftUpdateDefinitionValidator.validate(skillMarkdowns: [skill, skill], agentMarkdowns: []))
        let agent = """
        id: personal.default
        name: Personal Agent
        version: 1.0.0
        ---
        ## Skills
        text.normalize

        ## Rule
        Select only from declared skills.
        """
        XCTAssertThrowsError(try AgentOSSoftUpdateDefinitionValidator.validate(skillMarkdowns: [], agentMarkdowns: [agent, agent]))
    }

    func testInterruptedDownloadRemovesPartialStaging() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let staging = base.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let content = Data("remote content".utf8)
        let manifest = AgentOSSoftUpdateManifest(repository: "example/agentos", baseRevision: "initial",
            version: "1", revision: "r1", compatibility: "runtime-v1",
            files: [.init(path: "skills/demo.Skill.md", sha256: AgentOSSoftUpdateClient.sha256Hex(content),
                          byteCount: Int64(content.count), baseSHA256: "missing")])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestSHA = GitBlobSHA1.hash(manifestData)
        let fileSHA = GitBlobSHA1.hash(content)
        let commitSHA = String(repeating: "a", count: 40)
        let treeSHA = String(repeating: "b", count: 40)
        let transport = ScriptedSoftUpdateTransport(responses: [
            Self.response(["object": ["sha": commitSHA]]),
            Self.response(["tree": ["sha": treeSHA]]),
            Self.response(["sha": treeSHA, "truncated": false, "tree": [
                ["path": "agentos-update.json", "type": "blob", "sha": manifestSHA, "size": manifestData.count],
                ["path": "skills/demo.Skill.md", "type": "blob", "sha": fileSHA, "size": content.count]
            ]]),
            Self.response(["sha": manifestSHA, "encoding": "base64", "content": manifestData.base64EncodedString()])
        ], cancelAtRequest: 5)
        let client = try AgentOSSoftUpdateClient(location: GitHubRepositoryLocation(owner: "example", repository: "agentos"),
            transport: transport, tokenProvider: { "test-token" })
        do {
            _ = try await client.stageUpdate(currentRevision: "initial", runtimeCompatibility: "runtime-v1",
                workspaceURL: workspace, stagingRootURL: staging)
            XCTFail("Interrupted download should throw")
        } catch is CancellationError {
            // Expected: partial staging must be deleted.
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("skills/demo.Skill.md").path))
    }


}

private actor ScriptedSoftUpdateTransport: GitHubSyncHTTPTransport {
    private var responses: [GitHubSyncHTTPResponse]
    private var requests: [URLRequest] = []
    private let cancelAtRequest: Int?
    init(responses: [GitHubSyncHTTPResponse], cancelAtRequest: Int? = nil) {
        self.responses = responses
        self.cancelAtRequest = cancelAtRequest
    }
    func send(_ request: URLRequest) async throws -> GitHubSyncHTTPResponse {
        requests.append(request)
        if requests.count == cancelAtRequest { throw CancellationError() }
        guard !responses.isEmpty else { throw AgentOSSoftUpdateError.invalidRemoteResponse }
        return responses.removeFirst()
    }
    func recordedRequests() -> [URLRequest] { requests }
}
