import PAFoundation
import PAProviders
import PAMemory
import PASkills

public enum CognitionStage: String, Sendable, Codable, CaseIterable {
    case perception
    case context
    case reasoning
    case planning
    case actionProposal
    case verification
    case reflection
    case stateUpdate
}

public struct Perception: Sendable, Equatable {
    public let rawInput: String
    public let source: String

    public init(rawInput: String, source: String) {
        self.rawInput = rawInput
        self.source = source
    }
}

public struct ContextBundle: Sendable, Equatable {
    public let perception: Perception
    public let memoryIDs: [MemoryRecordID]
    public let skillIDs: [SkillID]

    public init(perception: Perception, memoryIDs: [MemoryRecordID], skillIDs: [SkillID]) {
        self.perception = perception
        self.memoryIDs = memoryIDs
        self.skillIDs = skillIDs
    }
}

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

public struct ActionProposal: Sendable, Equatable {
    public let actionID: ActionID
    public let planID: PlanID
    public let description: String
    public let capabilities: CapabilityLevel

    public init(
        actionID: ActionID = ActionID(),
        planID: PlanID,
        description: String,
        capabilities: CapabilityLevel
    ) {
        self.actionID = actionID
        self.planID = planID
        self.description = description
        self.capabilities = capabilities
    }
}

public struct VerificationResult: Sendable, Equatable {
    public let accepted: Bool
    public let notes: String

    public init(accepted: Bool, notes: String) {
        self.accepted = accepted
        self.notes = notes
    }
}

public struct Reflection: Sendable, Equatable {
    public let notes: String
    public let shouldAdapt: Bool

    public init(notes: String, shouldAdapt: Bool) {
        self.notes = notes
        self.shouldAdapt = shouldAdapt
    }
}

public protocol Planning: Sendable {
    func plan(goalID: GoalID, context: ContextBundle, reasoning: ReasoningResult) async throws -> Plan
}

public protocol Executing: Sendable {
    func propose(plan: Plan) async throws -> [ActionProposal]
}

public protocol CognitionPipelining: Sendable {
    func run(perception: Perception) async throws -> Reflection
}
