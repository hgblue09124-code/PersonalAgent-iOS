import PAKernel
import PAProviders

public struct ReasoningResult: Sendable, Equatable {
    public let summary: String
    public let providerID: ProviderID?
    public let modelID: ModelID?
    public init(summary: String, providerID: ProviderID?, modelID: ModelID?) {
        self.summary = summary
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct PlanStep: Sendable, Equatable {
    public let index: Int
    public let description: String
    public let skillID: SkillID?
    public init(index: Int, description: String, skillID: SkillID?) {
        self.index = index
        self.description = description
        self.skillID = skillID
    }
}

public struct Plan: Sendable, Equatable {
    public let id: PlanID
    public let goalID: GoalID
    public let steps: [PlanStep]
    public init(id: PlanID = PlanID(), goalID: GoalID, steps: [PlanStep]) {
        self.id = id
        self.goalID = goalID
        self.steps = steps
    }
}

public protocol ContextAssembling: Sendable {
    func assembleContext(
        perception: Perception,
        observations: [Observation],
        evaluation: Evaluation?
    ) async throws -> ContextBundle
}

public protocol Reasoning: Sendable {
    func reason(context: ContextBundle) async throws -> ReasoningResult
}

public protocol Planning: Sendable {
    func plan(goalID: GoalID, context: ContextBundle, reasoning: ReasoningResult) async throws -> Plan
}
