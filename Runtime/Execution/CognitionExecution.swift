import PAKernel

public struct ActionProposal: Sendable, Codable, Equatable {
    public let actionID: ActionID
    public let planID: PlanID
    public let toolID: ToolID?
    public let description: String
    public let capabilities: CapabilityLevel

    public init(
        actionID: ActionID = ActionID(),
        planID: PlanID,
        toolID: ToolID? = nil,
        description: String,
        capabilities: CapabilityLevel
    ) {
        self.actionID = actionID
        self.planID = planID
        self.toolID = toolID
        self.description = description
        self.capabilities = capabilities
    }
}

public protocol Executing: Sendable {
    func propose(plan: Plan) async throws -> [ActionProposal]
}
