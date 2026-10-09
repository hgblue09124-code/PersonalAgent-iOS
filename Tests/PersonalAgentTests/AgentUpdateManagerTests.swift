import XCTest
@testable import PARuntime

final class AgentUpdateManagerTests: XCTestCase {
    private func manifest(
        version: String = "1",
        revision: String = "r1",
        compatibility: String = "runtime-v1",
        checksum: String = "abc123"
    ) -> AgentUpdateManifest {
        AgentUpdateManifest(
            version: version,
            revision: revision,
            kind: .soft,
            compatibility: compatibility,
            checksum: checksum
        )
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
        } catch {
            XCTAssertEqual(error as? AgentUpdateError, .checksumMismatch)
        }
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
        } catch {
            XCTAssertEqual(error as? AgentUpdateError, .incompatible)
        }
        let state = await manager.state
        XCTAssertEqual(state, .staged)
    }

    func testRollbackWithoutActivatedSnapshotIsRejected() async {
        let manager = AgentUpdateManager()
        do {
            try await manager.rollback()
            XCTFail("Rollback without a snapshot must fail")
        } catch {
            XCTAssertEqual(error as? AgentUpdateError, .rollbackUnavailable)
        }
    }
}
