import Foundation

public enum AgentUpdateKind: String, Sendable {
    case soft
    case hard
}

public struct AgentUpdateManifest: Sendable, Equatable {
    public let version: String
    public let revision: String
    public let kind: AgentUpdateKind
    public let compatibility: String
    public let checksum: String

    public init(version: String, revision: String, kind: AgentUpdateKind, compatibility: String, checksum: String) {
        self.version = version
        self.revision = revision
        self.kind = kind
        self.compatibility = compatibility
        self.checksum = checksum
    }
}

public enum AgentUpdateState: Sendable, Equatable {
    case idle, downloaded, staged, validated, snapshotted, activated, rolledBack
}

public enum AgentUpdateError: Error, Equatable {
    case invalidManifest
    case incompatible
    case checksumMismatch
    case invalidTransition
    case rollbackUnavailable
}

/// A fail-closed transaction boundary for AgentOS definition updates.
/// Actual download, hashing, and workspace snapshot I/O remain injected responsibilities.
public actor AgentUpdateManager {
    public private(set) var state: AgentUpdateState = .idle
    public private(set) var activeManifest: AgentUpdateManifest?
    private var snapshotAvailable = false

    public init() {}

    public func download(_ manifest: AgentUpdateManifest) throws {
        guard state == .idle || state == .rolledBack else {
            throw AgentUpdateError.invalidTransition
        }
        guard !manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.compatibility.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.checksum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentUpdateError.invalidManifest
        }
        activeManifest = manifest
        snapshotAvailable = false
        state = .downloaded
    }

    public func stage() throws {
        guard state == .downloaded else { throw AgentUpdateError.invalidTransition }
        state = .staged
    }

    public func validate(runtimeCompatibility: String, actualChecksum: String) throws {
        guard state == .staged, let manifest = activeManifest else {
            throw AgentUpdateError.invalidTransition
        }
        guard manifest.compatibility == runtimeCompatibility else {
            throw AgentUpdateError.incompatible
        }
        guard manifest.checksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else {
            throw AgentUpdateError.checksumMismatch
        }
        state = .validated
    }

    public func snapshot() throws {
        guard state == .validated else { throw AgentUpdateError.invalidTransition }
        snapshotAvailable = true
        state = .snapshotted
    }

    public func activate() throws {
        guard state == .snapshotted else { throw AgentUpdateError.invalidTransition }
        state = .activated
    }

    public func rollback() throws {
        guard snapshotAvailable, state == .activated else {
            throw AgentUpdateError.rollbackUnavailable
        }
        state = .rolledBack
    }
}
