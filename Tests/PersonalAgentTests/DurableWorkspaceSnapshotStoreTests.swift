import XCTest
@testable import PAWorkspace

final class DurableWorkspaceSnapshotStoreTests: XCTestCase {
    func testSnapshotSurvivesStoreReopenAndRestoresFiles() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let snapshots = base.appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "before".write(to: workspace.appendingPathComponent("agent.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try "skill".write(to: workspace.appendingPathComponent("skills/demo.md"), atomically: true, encoding: .utf8)

        let store = try DurableWorkspaceSnapshotStore(directoryURL: snapshots)
        let snapshot = try await store.createSnapshot(of: workspace)
        try "after".write(to: workspace.appendingPathComponent("agent.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: workspace.appendingPathComponent("skills"))
        let reopened = try DurableWorkspaceSnapshotStore(directoryURL: snapshots)
        let persistedSnapshots = try await reopened.listSnapshots()
        XCTAssertEqual(persistedSnapshots.map(\.id), [snapshot.id])

        try await reopened.restore(snapshotID: snapshot.id, to: workspace)
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("agent.md"), encoding: .utf8), "before")
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("skills/demo.md"), encoding: .utf8), "skill")
    }

    func testRestoreRejectsCorruptedFileSizeBeforeReplacingWorkspace() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let snapshots = base.appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "good".write(to: workspace.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
        let store = try DurableWorkspaceSnapshotStore(directoryURL: snapshots)
        let snapshot = try await store.createSnapshot(of: workspace)
        let payload = snapshots.appendingPathComponent(snapshot.id).appendingPathComponent("data/state.txt")
        try "evil".write(to: payload, atomically: true, encoding: .utf8)

        do {
            try await store.restore(snapshotID: snapshot.id, to: workspace)
            XCTFail("Corrupt snapshots must fail closed")
        } catch let error as DurableWorkspaceSnapshotError {
            XCTAssertEqual(error, .verificationFailed("state.txt"))
        }
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("state.txt"), encoding: .utf8), "good")
    }

    func testSHA256MatchesKnownVector() {
        XCTAssertEqual(
            WorkspaceSHA256.digest(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSnapshotRejectsSymbolicLinks() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = base.appendingPathComponent("workspace")
        let snapshots = base.appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside.txt")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("link.txt"), withDestinationURL: outside)
        let store = try DurableWorkspaceSnapshotStore(directoryURL: snapshots)
        do {
            _ = try await store.createSnapshot(of: workspace)
            XCTFail("Snapshots must not follow symbolic links")
        } catch let error as DurableWorkspaceSnapshotError {
            XCTAssertEqual(error, .unsupportedFileType("link.txt"))
        }
    }
}
