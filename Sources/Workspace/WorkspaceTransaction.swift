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

/// Models activation and rollback of the in-memory workspace revision.
/// Durable filesystem snapshots must be provided by the persistence layer.
public actor WorkspaceTransaction {
    public private(set) var state: WorkspaceTransactionState = .idle
    public private(set) var active: WorkspaceSnapshot?
    public private(set) var previous: WorkspaceSnapshot?
    private var candidate: WorkspaceSnapshot?

    public init(initialSnapshot: WorkspaceSnapshot? = nil) {
        active = initialSnapshot
    }

    public func stage(_ snapshot: WorkspaceSnapshot) throws {
        guard state == .idle || state == .rolledBack else {
            throw WorkspaceTransactionError.invalidTransition
        }
        candidate = snapshot
        state = .staged
    }

    public func validate() throws {
        guard state == .staged, candidate != nil else {
            throw WorkspaceTransactionError.invalidTransition
        }
        state = .validated
    }

    public func snapshot() throws {
        guard state == .validated, candidate != nil else {
            throw WorkspaceTransactionError.invalidTransition
        }
        previous = active
        state = .snapshotted
    }

    public func activate() throws {
        guard state == .snapshotted, let candidate else {
            throw WorkspaceTransactionError.invalidTransition
        }
        active = candidate
        self.candidate = nil
        state = .activated
    }

    public func rollback() throws {
        guard state == .activated else {
            throw WorkspaceTransactionError.invalidTransition
        }
        active = previous
        candidate = nil
        state = .rolledBack
    }
}
