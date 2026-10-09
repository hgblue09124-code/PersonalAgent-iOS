import XCTest
@testable import PAWorkspace

final class WorkspaceTransactionTests: XCTestCase {
    func testActivationRetainsPriorRevisionAndPublishesCandidate() async throws {
        let original = WorkspaceSnapshot(identifier: "workspace-1", revision: "r1")
        let next = WorkspaceSnapshot(identifier: "workspace-1", revision: "r2")
        let transaction = WorkspaceTransaction(initialSnapshot: original)

        try await transaction.stage(next)
        try await transaction.validate()
        try await transaction.snapshot()
        try await transaction.activate()

        let state = await transaction.state
        let active = await transaction.active
        let previous = await transaction.previous
        XCTAssertEqual(state, .activated)
        XCTAssertEqual(active, next)
        XCTAssertEqual(previous, original)
    }

    func testRollbackRestoresPreviouslyActiveRevision() async throws {
        let original = WorkspaceSnapshot(identifier: "workspace-1", revision: "r1")
        let next = WorkspaceSnapshot(identifier: "workspace-1", revision: "r2")
        let transaction = WorkspaceTransaction(initialSnapshot: original)

        try await transaction.stage(next)
        try await transaction.validate()
        try await transaction.snapshot()
        try await transaction.activate()
        try await transaction.rollback()

        let state = await transaction.state
        let active = await transaction.active
        XCTAssertEqual(state, .rolledBack)
        XCTAssertEqual(active, original)
    }

    func testRollbackAllowsASecondTransaction() async throws {
        let original = WorkspaceSnapshot(identifier: "workspace-1", revision: "r1")
        let next = WorkspaceSnapshot(identifier: "workspace-1", revision: "r2")
        let final = WorkspaceSnapshot(identifier: "workspace-1", revision: "r3")
        let transaction = WorkspaceTransaction(initialSnapshot: original)

        try await transaction.stage(next)
        try await transaction.validate()
        try await transaction.snapshot()
        try await transaction.activate()
        try await transaction.rollback()
        try await transaction.stage(final)

        let state = await transaction.state
        let active = await transaction.active
        XCTAssertEqual(state, .staged)
        XCTAssertEqual(active, original)
    }

    func testInvalidTransitionFailsClosed() async {
        let transaction = WorkspaceTransaction()

        do {
            try await transaction.validate()
            XCTFail("Validation must not be allowed before staging")
        } catch {
            XCTAssertEqual(error as? WorkspaceTransactionError, .invalidTransition)
        }

        do {
            try await transaction.rollback()
            XCTFail("Rollback must not be allowed before activation")
        } catch {
            XCTAssertEqual(error as? WorkspaceTransactionError, .invalidTransition)
        }
    }
}
