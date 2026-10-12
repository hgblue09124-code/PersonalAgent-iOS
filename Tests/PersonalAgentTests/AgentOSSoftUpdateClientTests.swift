import XCTest
@testable import PAWorkspace

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
}
