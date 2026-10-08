import XCTest
@testable import PAWorkspace

final class GitBackedWorkspaceTests: XCTestCase {
    func testRepositoryOperationsAreDelegatedWithoutShellAccess() async throws {
        let workspace = LocalAgentWorkspace(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let fake = FakeRepository()
        let git = GitBackedWorkspace(workspace: workspace, repository: fake)
        XCTAssertEqual(try await git.status().branch, "main")
        XCTAssertEqual(try await git.log().first?.message, "initial")
        try await git.checkout(branch: "agent")
        XCTAssertEqual(await fake.lastCheckout, "agent")
    }
}

private actor FakeRepository: AgentRepository {
    var lastCheckout: String?
    func status() async throws -> RepositoryStatus { RepositoryStatus(branch: "main", isClean: true) }
    func diff() async throws -> RepositoryDiff { RepositoryDiff(paths: [], patch: "") }
    func log(limit: Int) async throws -> [RepositoryCommit] { [RepositoryCommit(id: "1", message: "initial")] }
    func branches() async throws -> [RepositoryBranch] { [RepositoryBranch(name: "main", isCurrent: true)] }
    func remotes() async throws -> [RepositoryRemote] { [] }
    func checkout(branch: String) async throws { lastCheckout = branch }
    func pull() async throws {}
    func commit(message: String) async throws -> RepositoryCommit { RepositoryCommit(id: "2", message: message) }
    func push() async throws {}
}
