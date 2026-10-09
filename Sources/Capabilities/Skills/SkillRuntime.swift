import Foundation

public struct SkillExecutionRequest: Sendable, Equatable {
    public let skillID: String
    public let moduleID: String
    public let input: String
    public init(skillID: String, moduleID: String, input: String) {
        self.skillID = skillID; self.moduleID = moduleID; self.input = input
    }
}

public enum SkillExecutionError: Error, Sendable, Equatable {
    case missingSkill(String)
    case missingModule(String)
    case disabledSkill(String)
    case malformedSkill
    case scopeMismatch
}

public struct SkillRuntime: Sendable {
    public typealias ModuleHandler = @Sendable (String) async throws -> String
    private let skills: [String: SkillDefinition]
    private let modules: [String: ModuleHandler]
    private let disabled: Set<String>

    public init(skills: [SkillDefinition] = [], modules: [String: ModuleHandler] = [:], disabled: Set<String> = []) {
        self.skills = skills.reduce(into: [:]) { result, skill in
            // Duplicate identities must not trap runtime initialization; first definition wins.
            if result[skill.identity] == nil {
                result[skill.identity] = skill
            }
        }
        self.modules = modules
        self.disabled = disabled
    }

    public func run(_ request: SkillExecutionRequest) async throws -> String {
        guard let skill = skills[request.skillID] else { throw SkillExecutionError.missingSkill(request.skillID) }
        guard !disabled.contains(skill.identity) else { throw SkillExecutionError.disabledSkill(skill.identity) }
        guard skill.identity == request.skillID else { throw SkillExecutionError.scopeMismatch }
        guard let module = modules[request.moduleID] else { throw SkillExecutionError.missingModule(request.moduleID) }
        return try await module(request.input)
    }
}
