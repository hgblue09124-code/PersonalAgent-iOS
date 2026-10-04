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
}
