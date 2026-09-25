import PAFoundation

public struct PolicyDecision: Sendable, Equatable {
    public let allowed: Bool
    public let requiresApproval: Bool
    public let reason: String

    public init(allowed: Bool, requiresApproval: Bool, reason: String) {
        self.allowed = allowed
        self.requiresApproval = requiresApproval
        self.reason = reason
    }

    public static func allow(_ reason: String = "permitted") -> PolicyDecision {
        PolicyDecision(allowed: true, requiresApproval: false, reason: reason)
    }

    public static func approve(_ reason: String) -> PolicyDecision {
        PolicyDecision(allowed: false, requiresApproval: true, reason: reason)
    }

    public static func deny(_ reason: String) -> PolicyDecision {
        PolicyDecision(allowed: false, requiresApproval: false, reason: reason)
    }
}

public struct ActionIntent: Sendable, Equatable {
    public let actionID: ActionID
    public let toolID: ToolID?
    public let capabilities: CapabilityLevel
    public let summary: String

    public init(
        actionID: ActionID = ActionID(),
        toolID: ToolID? = nil,
        capabilities: CapabilityLevel,
        summary: String
    ) {
        self.actionID = actionID
        self.toolID = toolID
        self.capabilities = capabilities
        self.summary = summary
    }
}

public protocol PolicyEvaluating: Sendable {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision
}

public protocol ApprovalGate: Sendable {
    func requestApproval(for intent: ActionIntent) async throws -> Bool
}
