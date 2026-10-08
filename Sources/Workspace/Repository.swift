import Foundation

public struct RepositoryStatus: Sendable, Equatable {
    public let branch: String
    public let isClean: Bool
    public let changedPaths: [String]
    public init(branch: String, isClean: Bool, changedPaths: [String] = []) { self.branch = branch; self.isClean = isClean; self.changedPaths = changedPaths }
}

public struct RepositoryDiff: Sendable, Equatable {
    public let paths: [String]
    public let patch: String
    public init(paths: [String], patch: String) { self.paths = paths; self.patch = patch }
}

public struct RepositoryCommit: Sendable, Equatable {
    public let id: String
    public let message: String
    public let author: String?
    public init(id: String, message: String, author: String? = nil) { self.id = id; self.message = message; self.author = author }
}

public struct RepositoryBranch: Sendable, Equatable {
    public let name: String
    public let isCurrent: Bool
    public init(name: String, isCurrent: Bool) { self.name = name; self.isCurrent = isCurrent }
}

public struct RepositoryRemote: Sendable, Equatable {
    public let name: String
    public let address: String
    public init(name: String, address: String) { self.name = name; self.address = address }
}

public enum RepositoryError: Error, Sendable, Equatable {
    case unavailable
    case invalidOperation
    case conflict
    case authenticationRequired
}

public protocol AgentRepository: Sendable {
    func status() async throws -> RepositoryStatus
    func diff() async throws -> RepositoryDiff
    func log(limit: Int) async throws -> [RepositoryCommit]
    func branches() async throws -> [RepositoryBranch]
    func remotes() async throws -> [RepositoryRemote]
    func checkout(branch: String) async throws
    func pull() async throws
    func commit(message: String) async throws -> RepositoryCommit
    func push() async throws
}

public actor GitBackedWorkspace {
    public let workspace: AgentWorkspace
    public let repository: AgentRepository

    public init(workspace: AgentWorkspace, repository: AgentRepository) {
        self.workspace = workspace
        self.repository = repository
    }

    public func status() async throws -> RepositoryStatus { try await repository.status() }
    public func diff() async throws -> RepositoryDiff { try await repository.diff() }
    public func log(limit: Int = 20) async throws -> [RepositoryCommit] { try await repository.log(limit: limit) }
    public func branches() async throws -> [RepositoryBranch] { try await repository.branches() }
    public func remotes() async throws -> [RepositoryRemote] { try await repository.remotes() }
    public func checkout(branch: String) async throws { try await repository.checkout(branch: branch) }
    public func pull() async throws { try await repository.pull() }
    public func commit(message: String) async throws -> RepositoryCommit { try await repository.commit(message: message) }
    public func push() async throws { try await repository.push() }
}
