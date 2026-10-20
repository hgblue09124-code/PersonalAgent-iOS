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
        #expect(manifest.metadata["executor"] == "text.normalize")
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
            .appendingPathComponent("skills-\(UUID().uuidString)", isDirectory: true)
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
            .appendingPathComponent("skills-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSkillStore(directoryURL: directory)
        try await store.ensureDefaultSkill()
        try await store.ensureDefaultSkill()

        let found = try await store.discover(query: "text.normalize")
        #expect(found.count == 1)
        #expect(found.first?.metadata["source"] == "Skill.md")
        #expect(found.first?.metadata["executor"] == "text.normalize")
    }

    @Test("migrates legacy canonical workspace Skill bindings idempotently")
    func migratesLegacyWorkspaceSkillBindings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-migrate-\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let cases: [(id: String, name: String, input: String, output: String, moduleID: String, adapter: String)] = [
            ("workspace.create-file", "Tạo File", "tool.workspace.write.input", "tool.workspace.write.output", "tool.workspace.write", "workspace.create-file"),
            ("workspace.search", "Tìm kiếm Workspace", "tool.workspace.read.input", "tool.workspace.read.output", "tool.workspace.read", "workspace.search"),
            ("workspace.read-file", "Read / Đọc File", "tool.workspace.read.input", "tool.workspace.read.output", "tool.workspace.read", "workspace.read-file")
        ]

        for item in cases {
            let markdown = """
            id: \\(item.id)
            name: \\(item.name)
            version: 1.0.0
            description: Existing user-visible built-in Skill.
            ---
            ## Input
            \\(item.input)

            ## Output
            \\(item.output)

            ## Rule
            Preserve this installed rule during migration.
            """
            try markdown.write(
                to: directory.appendingPathComponent("\\(item.id).Skill.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = FileSkillStore(directoryURL: directory)
        try await store.ensureDefaultSkill()
        let migratedContents = try cases.map { item in
            try String(contentsOf: directory.appendingPathComponent("\\(item.id).Skill.md"), encoding: .utf8)
        }

        for item in cases {
            let manifest = try await store.load(id: SkillID(rawValue: item.id))
            #expect(manifest.metadata["moduleID"] == item.moduleID)
            #expect(manifest.metadata["chatInputAdapter"] == item.adapter)
            #expect(manifest.instructions == "Preserve this installed rule during migration.")
        }

        try await store.ensureDefaultSkill()
        let secondPassContents = try cases.map { item in
            try String(contentsOf: directory.appendingPathComponent("\\(item.id).Skill.md"), encoding: .utf8)
        }
        #expect(migratedContents == secondPassContents)
    }

    @Test("does not rewrite conflicting or schema-mismatched workspace Skills")
    func refusesUnsafeWorkspaceSkillMigration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-no-migrate-\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let conflicting = """
        id: workspace.create-file
        name: Custom create-file Skill
        version: 1.0.0
        moduleID: tool.workspace.write
        chatInputAdapter: untrusted.adapter
        ---
        ## Input
        tool.workspace.write.input

        ## Output
        tool.workspace.write.output

        ## Rule
        Keep the conflicting binding untouched.
        """
        let mismatchedSchema = """
        id: workspace.search
        name: Custom search Skill
        version: 1.0.0
        ---
        ## Input
        custom.search.input

        ## Output
        tool.workspace.read.output

        ## Rule
        Keep the schema mismatch untouched.
        """
        let conflictingURL = directory.appendingPathComponent("workspace.create-file.Skill.md")
        let mismatchedURL = directory.appendingPathComponent("workspace.search.Skill.md")
        try conflicting.write(to: conflictingURL, atomically: true, encoding: .utf8)
        try mismatchedSchema.write(to: mismatchedURL, atomically: true, encoding: .utf8)

        let store = FileSkillStore(directoryURL: directory)
        try await store.ensureDefaultSkill()

        #expect(try String(contentsOf: conflictingURL, encoding: .utf8) == conflicting)
        #expect(try String(contentsOf: mismatchedURL, encoding: .utf8) == mismatchedSchema)
    }

}
