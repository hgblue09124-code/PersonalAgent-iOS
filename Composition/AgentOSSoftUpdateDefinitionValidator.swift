import Foundation
import PASkills

public enum AgentOSSoftUpdateDefinitionValidationError: Error, Sendable, Equatable {
    case duplicateSkillID(String)
    case duplicateAgentID(String)
}

/// Validates the complete active-plus-updated Markdown set before any workspace writes.
public enum AgentOSSoftUpdateDefinitionValidator {
    public static func validate(skillMarkdowns: [String], agentMarkdowns: [String]) throws {
        let skillParser = SkillMarkdownParser()
        var skillIDs = Set<String>()
        for markdown in skillMarkdowns {
            let skill = try skillParser.parse(markdown)
            guard skillIDs.insert(skill.id.rawValue).inserted else {
                throw AgentOSSoftUpdateDefinitionValidationError.duplicateSkillID(skill.id.rawValue)
            }
        }
        let agentParser = AgentMarkdownParser()
        var agentIDs = Set<String>()
        for markdown in agentMarkdowns {
            let agent = try agentParser.parse(markdown)
            guard agentIDs.insert(agent.id).inserted else {
                throw AgentOSSoftUpdateDefinitionValidationError.duplicateAgentID(agent.id)
            }
        }
    }
}
