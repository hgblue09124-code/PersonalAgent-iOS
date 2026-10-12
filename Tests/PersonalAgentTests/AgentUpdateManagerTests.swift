import XCTest
@testable import PARuntime

final class AgentUpdateManagerTests: XCTestCase {
    private func manifest(version: String = "1", revision: String = "r1", compatibility: String = "runtime-v1",
                          checksum: String = "abc123", repository: String? = nil, baseRevision: String? = nil,
                          files: [AgentUpdateFile] = []) -> AgentUpdateManifest {
        AgentUpdateManifest(version: version, revision: revision, kind: .soft, compatibility: compatibility,
                            checksum: checksum, repository: repository, baseRevision: baseRevision, files: files)
    }

    func testUpdateMustValidateBeforeActivationAndCanRollback() async throws {
        let manager = AgentUpdateManager()
        try await manager.download(manifest())
        try await manager.stage()
        try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "ABC123")
        try await manager.snapshot()
        try await manager.activate()
        let activatedState = await manager.state
        XCTAssertEqual(activatedState, .activated)
        try await manager.rollback()
        let rolledBackState = await manager.state
        XCTAssertEqual(rolledBackState, .rolledBack)
    }

    func testChecksumMismatchFailsClosed() async throws {
        let manager = AgentUpdateManager()
        try await manager.download(manifest())
        try await manager.stage()
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "wrong")
            XCTFail("Checksum mismatch must block activation")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .checksumMismatch) }
        let state = await manager.state
        XCTAssertEqual(state, .staged)
    }

    func testIncompatibleRuntimeFailsClosed() async throws {
        let manager = AgentUpdateManager()
        try await manager.download(manifest())
        try await manager.stage()
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v2", actualChecksum: "abc123")
            XCTFail("Incompatible updates must be rejected")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .incompatible) }
        let state = await manager.state
        XCTAssertEqual(state, .staged)
    }

    func testRollbackWithoutActivatedSnapshotIsRejected() async {
        let manager = AgentUpdateManager()
        do { try await manager.rollback(); XCTFail("Rollback without a snapshot must fail") }
        catch { XCTAssertEqual(error as? AgentUpdateError, .rollbackUnavailable) }
    }

    func testUnsafeAndExecutablePathsAreRejected() {
        XCTAssertFalse(AgentUpdateManager.isAllowedPath("../skills/evil.md"))
        XCTAssertFalse(AgentUpdateManager.isAllowedPath("/skills/evil.md"))
        XCTAssertFalse(AgentUpdateManager.isAllowedPath("skills/../../evil.md"))
        XCTAssertFalse(AgentUpdateManager.isAllowedPath("skills/run.swift"))
        XCTAssertFalse(AgentUpdateManager.isAllowedPath("unknown/file.md"))
        XCTAssertTrue(AgentUpdateManager.isAllowedPath("skills/demo/SKILL.md"))
        XCTAssertTrue(AgentUpdateManager.isAllowedPath("agents/Agent.md"))
    }

    func testDuplicatePathsAreRejected() async {
        let file = AgentUpdateFile(path: "skills/demo/SKILL.md", sha256: String(repeating: "a", count: 64), byteCount: 12)
        do { try await AgentUpdateManager().download(manifest(files: [file, file])); XCTFail("Duplicate paths must fail") }
        catch { XCTAssertEqual(error as? AgentUpdateError, .invalidFileMetadata(file.path)) }
    }

    func testRepositoryBaseAndLocalEditsMustMatch() async throws {
        let file = AgentUpdateFile(path: "skills/demo/SKILL.md", sha256: String(repeating: "b", count: 64), byteCount: 12)
        let manager = AgentUpdateManager()
        try await manager.download(manifest(repository: "owner/repo", baseRevision: "base", files: [file]))
        try await manager.stage()
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "abc123",
                                       repository: "other/repo", currentRevision: "base", actualFiles: [file.path])
            XCTFail("Repository mismatch must fail")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .repositoryMismatch) }
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "abc123",
                                       repository: "owner/repo", currentRevision: "stale", actualFiles: [file.path])
            XCTFail("Stale base revision must fail")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .baseRevisionMismatch) }
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "abc123",
                                       repository: "owner/repo", currentRevision: "base", actualFiles: [file.path],
                                       locallyModifiedPaths: [file.path])
            XCTFail("Local edits must not be overwritten")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .localConflict(file.path)) }
        let state = await manager.state
        XCTAssertEqual(state, .staged)
    }

    func testManifestDecodeRejectsMalformedAndHardUpdates() throws {
        XCTAssertThrowsError(try AgentUpdateManager.decodeManifest(Data("not-json".utf8)))
        let invalid = #"{"version":"1","revision":"r1","kind":"hard","compatibility":"runtime-v1","checksum":"abc123","files":[]}"#
        XCTAssertThrowsError(try AgentUpdateManager.decodeManifest(Data(invalid.utf8)))
    }

    func testUnexpectedStagedFilesAreRejected() async throws {
        let file = AgentUpdateFile(path: "skills/demo/SKILL.md", sha256: String(repeating: "c", count: 64), byteCount: 12)
        let manager = AgentUpdateManager()
        try await manager.download(manifest(files: [file]))
        try await manager.stage()
        do {
            try await manager.validate(runtimeCompatibility: "runtime-v1", actualChecksum: "abc123",
                                       actualFiles: [file.path, "skills/extra.md"])
            XCTFail("Unexpected staged files must be rejected")
        } catch { XCTAssertEqual(error as? AgentUpdateError, .unexpectedFile("skills/extra.md")) }
    }
}
