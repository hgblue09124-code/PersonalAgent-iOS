import XCTest
@testable import PAWorkspace

final class WorkspaceTransactionTests: XCTestCase {
    func testOrderedActivationRetainsPreviousSnapshot() async throws {
        let transaction = WorkspaceTransaction()
        let snapshot = WorkspaceSnapshot(identifier: "workspace-1", revision: "r2")

        try await transaction.stage(snapshot)
        try await transaction.validate()
        try await transaction.snapshot()
        try await transaction.activate()

        let state = await transaction.state
        let previous = await transaction.previous
        XCTAssertEqual(state, .activated)
        XCTAssertEqual(previous, snapshot)
    }

    func testRollbackAllowsASecondTransaction() async throws {
        let transaction = WorkspaceTransaction()
        let original = WorkspaceSnapshot(identifier: "workspace-1", revision: "r2")
        let next = WorkspaceSnapshot(identifier: "workspace-1", revision: "r3")

        try await transaction.stage(original)
        try await transaction.validate()
        try await transaction.snapshot()
        try await transaction.activate()
        try await transaction.rollback()
        try await transaction.stage(next)

        let state = await transaction.state
        let previous = await transaction.previous
        XCTAssertEqual(state, .staged)
        XCTAssertEqual(previous, next)
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
