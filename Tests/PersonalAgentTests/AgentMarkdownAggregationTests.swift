import Foundation
import Testing
import PAKernel
import PASkills

@Suite("Agent Markdown Aggregation")
struct AgentMarkdownAggregationTests {
    @Test("parses Agent.md skill aggregation")
    func parsesAgentMarkdown() throws {
        let markdown = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent skill set.
        ---
        ## Skills
        text.normalize

        ## Rule
        Select one declared skill for the current goal.
        """

        let manifest = try AgentMarkdownParser().parse(markdown)
        #expect(manifest.id == "personal.default")
        #expect(manifest.skillIDs.map(\.rawValue) == ["text.normalize"])
        #expect(manifest.instructions.contains("Select one declared skill"))
    }

    @Test("rejects duplicate skill declarations")
    func rejectsDuplicateSkills() {
        let markdown = """
        id: duplicate.agent
        name: Duplicate Agent
        version: 1.0.0
        ---
        ## Skills
        text.normalize
        text.normalize
        """

        #expect(throws: AgentMarkdownError.duplicateSkill("text.normalize")) {
            try AgentMarkdownParser().parse(markdown)
        }
    }
}
