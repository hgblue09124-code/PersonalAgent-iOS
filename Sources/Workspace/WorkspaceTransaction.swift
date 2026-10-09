public enum WorkspaceTransactionState: Sendable, Equatable {
    case idle
    case staged
    case validated
    case snapshotted
    case activated
    case rolledBack
}

public struct WorkspaceSnapshot: Sendable, Equatable {
    public let identifier: String
    public let revision: String

    public init(identifier: String, revision: String) {
        self.identifier = identifier
        self.revision = revision
    }
}

public enum WorkspaceTransactionError: Error, Equatable {
    case invalidTransition
}

/// Enforces the workspace activation order and retains the prior snapshot for recovery.
public actor WorkspaceTransaction {
    public private(set) var state: WorkspaceTransactionState = .idle
    public private(set) var previous: WorkspaceSnapshot?

    public init() {}

    public func stage(_ snapshot: WorkspaceSnapshot) throws {
        guard state == .idle || state == .rolledBack else {
            throw WorkspaceTransactionError.invalidTransition
        }
        previous = snapshot
        state = .staged
    }

    public func validate() throws {
        guard state == .staged else {
            throw WorkspaceTransactionError.invalidTransition
        }
        state = .validated
    }

    public func snapshot() throws {
        guard state == .validated else {
            throw WorkspaceTransactionError.invalidTransition
        }
        state = .snapshotted
    }

    public func activate() throws {
        guard state == .snapshotted else {
            throw WorkspaceTransactionError.invalidTransition
        }
        state = .activated
    }

    public func rollback() throws {
        guard state == .activated else {
            throw WorkspaceTransactionError.invalidTransition
        }
        state = .rolledBack
    }
}
