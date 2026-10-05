import Foundation
import Testing
import PAKernel
import PASkills

@Suite("Skill Markdown Persistence")
struct SkillMarkdownPersistenceTests {
    @Test("parses canonical Skill.md grammar and rule")
    func parsesSkillMarkdown() throws {
        let markdown = """
        id: text.normalize
        name: Text Normalize
        version: 1.0.0
        description: Normalize user text.
        ---
        ## Input
        skill.text.normalize.in

        ## Output
        skill.text.normalize.out

        ## Rule
        Trim surrounding whitespace.
        """

        let manifest = try SkillMarkdownParser().parse(markdown)
        #expect(manifest.id.rawValue == "text.normalize")
        #expect(manifest.name == "Text Normalize")
        #expect(manifest.instructions == "Trim surrounding whitespace.")
        #expect(manifest.inputSchema.identifier == "skill.text.normalize.in")
        #expect(manifest.outputSchema.identifier == "skill.text.normalize.out")
        #expect(manifest.metadata["executor"] == nil)
    }

    @Test("parses explicit executor binding")
    func parsesExplicitExecutorBinding() throws {
        let markdown = """
        id: text.normalize.custom
        name: Text Normalize Custom
        version: 1.0.0
        description: Normalize text with the registered executor.
        executor: text.normalize
        ---
        ## Input
        in

        ## Output
        out

        ## Rule
        Trim surrounding whitespace.
        """

        let manifest = try SkillMarkdownParser().parse(markdown)
        #expect(manifest.metadata["executor"] == "text.normalize")
    }

    @Test("parses Agent.md skill aggregation")
    func parsesAgentMarkdown() throws {
        let markdown = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent.
        ---
        ## Skills
        text.normalize
        another.skill

        ## Rule
        Select only from declared skills.
        """

        let agent = try AgentMarkdownParser().parse(markdown)
        #expect(agent.id == "personal.default")
        #expect(agent.skillIDs.map { $0.rawValue } == ["text.normalize", "another.skill"])
        #expect(agent.instructions == "Select only from declared skills.")
    }

    @Test("rejects duplicate Agent.md skills")
    func rejectsDuplicateAgentSkills() throws {
        let markdown = """
        id: personal.default
        name: Personal Default Agent
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

    @Test("file store discovers Skill.md files")
    func fileStoreDiscoversSkills() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("normalize.Skill.md")
        let markdown = """
        id: text.normalize
        name: Text Normalize
        version: 1.0.0
        description: Normalize user text.
        ---
        ## Input
        in

        ## Output
        out

        ## Rule
        Trim surrounding whitespace.
        """
        try markdown.write(to: file, atomically: true, encoding: .utf8)

        let store = FileSkillStore(directoryURL: directory)
        let found = try await store.discover(query: "normalize")
        #expect(found.count == 1)
        #expect(found.first?.id.rawValue == "text.normalize")
    }

    @Test("file store seeds the canonical default Skill.md once")
    func seedsDefaultSkill() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-seed-(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSkillStore(directoryURL: directory)
        try await store.ensureDefaultSkill()
        try await store.ensureDefaultSkill()

        let found = try await store.discover(query: "text.normalize")
        #expect(found.count == 1)
        #expect(found.first?.metadata["source"] == "Skill.md")
        #expect(found.first?.metadata["executor"] == "text.normalize")
    }
}
