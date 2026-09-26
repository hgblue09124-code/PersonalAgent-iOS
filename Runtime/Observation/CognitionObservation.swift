import PAKernel
import PAMemory

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
