import Foundation

/// Operations an Agent must be explicitly authorized to perform.
public enum AgentPermission: String, Sendable, CaseIterable {
    case readWorkspace = "READ_WORKSPACE"
    case writeWorkspace = "WRITE_WORKSPACE"
    case executeSkill = "EXECUTE_SKILL"
    case executeModule = "EXECUTE_MODULE"
    case network = "NETWORK"
    case repositoryRead = "GITHUB_READ"
    case repositoryWrite = "GITHUB_WRITE"
    case modelAccess = "MODEL_ACCESS"
    case memoryRead = "MEMORY_READ"
    case memoryWrite = "MEMORY_WRITE"
}

public struct AgentPermissionSet: Sendable, Equatable {
    public let values: Set<AgentPermission>

    public init(_ values: Set<AgentPermission> = []) {
        self.values = values
    }

    public func allows(_ permission: AgentPermission) -> Bool {
        values.contains(permission)
    }
}

public enum AgentAuthorizationError: Error, Equatable {
    case denied(AgentPermission)
}

/// Fail-closed authorization contract for Kernel-facing Agent operations.
public struct AgentAuthorizer: Sendable {
    public let permissions: AgentPermissionSet

    public init(permissions: AgentPermissionSet = AgentPermissionSet()) {
        self.permissions = permissions
    }

    public func require(_ permission: AgentPermission) throws {
        guard permissions.allows(permission) else {
            throw AgentAuthorizationError.denied(permission)
        }
    }

    public func requireAll<S: Sequence>(_ requested: S) throws where S.Element == AgentPermission {
        for permission in requested {
            try require(permission)
        }
    }
}
