import Foundation
import Testing
import PAKernel
import PASkills
import PAMemory
import PAStorageMemory

@Suite("Contract Boundary Regression Matrix")
struct ContractBoundaryRegressionTests {
    private let skillBase = """
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

    private let agentBase = """
    id: personal.default
    name: Personal Default Agent
    version: 1.0.0
    description: Default personal agent.
    ---
    ## Skills
    text.normalize

    ## Rule
    Select only from the declared skills.
    """

    @Test("skill accepts canonical document") func skillCanonical() throws {
        let value = try SkillMarkdownParser().parse(skillBase)
        #expect(value.id.rawValue == "text.normalize")
        #expect(value.name == "Text Normalize")
        #expect(value.version == SemanticVersion(major: 1, minor: 0, patch: 0))
        #expect(value.inputSchema.identifier == "skill.text.normalize.in")
        #expect(value.outputSchema.identifier == "skill.text.normalize.out")
        #expect(value.instructions == "Trim surrounding whitespace.")
    }

    @Test("skill normalizes CRLF") func skillCRLF() throws {
        let value = try SkillMarkdownParser().parse(skillBase.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(value.id.rawValue == "text.normalize")
        #expect(value.instructions == "Trim surrounding whitespace.")
    }

    @Test("skill trims identity") func skillTrimmedIdentity() throws {
        let source = skillBase.replacingOccurrences(of: "id: text.normalize", with: "id:   text.normalize   ")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.id.rawValue == "text.normalize")
    }

    @Test("skill trims executor") func skillTrimmedExecutor() throws {
        let source = skillBase.replacingOccurrences(of: "description: Normalize user text.", with: "description: Normalize user text.\nexecutor:   text.normalize   ")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.metadata["executor"] == "text.normalize")
    }

    @Test("skill defaults executor to identity") func skillDefaultExecutor() throws {
        let value = try SkillMarkdownParser().parse(skillBase)
        #expect(value.metadata["executor"] == "text.normalize")
    }

    @Test("skill rejects missing input section") func skillMissingInput() throws {
        let source = skillBase.replacingOccurrences(of: "## Input\nskill.text.normalize.in\n\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("Input")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing output section") func skillMissingOutput() throws {
        let source = skillBase.replacingOccurrences(of: "## Output\nskill.text.normalize.out\n\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("Output")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing rule section") func skillMissingRule() throws {
        let source = skillBase.replacingOccurrences(of: "## Rule\nTrim surrounding whitespace.\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("Rule")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects empty input") func skillEmptyInput() throws {
        let source = skillBase.replacingOccurrences(of: "skill.text.normalize.in", with: "    ")
        #expect(throws: SkillMarkdownError.missingField("Input")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects empty output") func skillEmptyOutput() throws {
        let source = skillBase.replacingOccurrences(of: "skill.text.normalize.out", with: "    ")
        #expect(throws: SkillMarkdownError.missingField("Output")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects empty rule") func skillEmptyRule() throws {
        let source = skillBase.replacingOccurrences(of: "Trim surrounding whitespace.", with: "    ")
        #expect(throws: SkillMarkdownError.missingField("Rule")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects duplicate delimiter") func skillDuplicateDelimiter() throws {
        let source = skillBase + "\n---\n"
        #expect(throws: SkillMarkdownError.invalidSchema("expected exactly one document delimiter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects leading delimiter") func skillLeadingDelimiter() throws {
        let source = "---\n" + skillBase
        #expect(throws: SkillMarkdownError.invalidSchema("expected exactly one document delimiter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing delimiter") func skillMissingDelimiter() throws {
        let source = skillBase.replacingOccurrences(of: "\n---\n", with: "\n")
        #expect(throws: SkillMarkdownError.invalidSchema("expected exactly one document delimiter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects malformed front matter") func skillMalformedFrontMatter() throws {
        let source = skillBase.replacingOccurrences(of: "description: Normalize user text.", with: "description Normalize user text.")
        #expect(throws: SkillMarkdownError.missingField("malformed front matter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects empty front matter value") func skillEmptyFrontMatterValue() throws {
        let source = skillBase.replacingOccurrences(of: "name: Text Normalize", with: "name: ")
        #expect(throws: SkillMarkdownError.missingField("malformed front matter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects invalid front matter key") func skillInvalidFrontMatterKey() throws {
        let source = skillBase.replacingOccurrences(of: "name: Text Normalize", with: "na.me: Text Normalize")
        #expect(throws: SkillMarkdownError.invalidSchema("invalid field name: na.me")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects duplicate front matter field") func skillDuplicateFrontMatter() throws {
        let source = skillBase.replacingOccurrences(of: "description: Normalize user text.", with: "description: Normalize user text.\ndescription: Again")
        #expect(throws: SkillMarkdownError.missingField("duplicate field: description")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing id") func skillMissingID() throws {
        let source = skillBase.replacingOccurrences(of: "id: text.normalize\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("id")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects blank id") func skillBlankID() throws {
        let source = skillBase.replacingOccurrences(of: "id: text.normalize", with: "id:   ")
        #expect(throws: SkillMarkdownError.missingField("malformed front matter")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing name") func skillMissingName() throws {
        let source = skillBase.replacingOccurrences(of: "name: Text Normalize\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("name")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects missing version") func skillMissingVersion() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0\n", with: "")
        #expect(throws: SkillMarkdownError.missingField("version")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects two component version") func skillVersionTwoComponents() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0", with: "version: 1.0")
        #expect(throws: SkillMarkdownError.invalidVersion("1.0")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects four component version") func skillVersionFourComponents() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0", with: "version: 1.0.0.0")
        #expect(throws: SkillMarkdownError.invalidVersion("1.0.0.0")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects negative version") func skillNegativeVersion() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0", with: "version: -1.0.0")
        #expect(throws: SkillMarkdownError.invalidVersion("-1.0.0")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects alphabetic version") func skillAlphabeticVersion() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0", with: "version: one.0.0")
        #expect(throws: SkillMarkdownError.invalidVersion("one.0.0")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects empty version component") func skillEmptyVersionComponent() throws {
        let source = skillBase.replacingOccurrences(of: "version: 1.0.0", with: "version: 1..0")
        #expect(throws: SkillMarkdownError.invalidVersion("1..0")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects duplicate input section") func skillDuplicateInput() throws {
        let source = skillBase.replacingOccurrences(of: "\n## Output", with: "\n## Input\nanother.input\n\n## Output")
        #expect(throws: SkillMarkdownError.missingField("duplicate section: Input")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects duplicate output section") func skillDuplicateOutput() throws {
        let source = skillBase.replacingOccurrences(of: "\n## Rule", with: "\n## Output\nanother.output\n\n## Rule")
        #expect(throws: SkillMarkdownError.missingField("duplicate section: Output")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill rejects duplicate rule section") func skillDuplicateRule() throws {
        let source = skillBase + "\n## Rule\nAnother rule.\n"
        #expect(throws: SkillMarkdownError.missingField("duplicate section: Rule")) {
            try SkillMarkdownParser().parse(source)
        }
    }

    @Test("skill preserves multiline rule") func skillMultilineRule() throws {
        let source = skillBase.replacingOccurrences(of: "Trim surrounding whitespace.", with: "    Trim surrounding whitespace.\nDo not mutate internal spacing.")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.instructions.contains("Do not mutate internal spacing."))
    }

    @Test("skill preserves multiline schema identifiers") func skillMultilineSchema() throws {
        let source = skillBase.replacingOccurrences(of: "skill.text.normalize.in", with: "    skill.text.normalize.in\nschema-v1")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.inputSchema.identifier.contains("schema-v1"))
    }

    @Test("agent accepts canonical document") func agentCanonical() throws {
        let value = try AgentMarkdownParser().parse(agentBase)
        #expect(value.id == "personal.default")
        #expect(value.name == "Personal Default Agent")
        #expect(value.skillIDs.map(\.rawValue) == ["text.normalize"])
        #expect(value.instructions == "Select only from the declared skills.")
    }

    @Test("agent normalizes CRLF") func agentCRLF() throws {
        let value = try AgentMarkdownParser().parse(agentBase.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(value.id == "personal.default")
        #expect(value.skillIDs.count == 1)
    }

    @Test("agent trims id") func agentTrimmedID() throws {
        let source = agentBase.replacingOccurrences(of: "id: personal.default", with: "id:   personal.default   ")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.id == "personal.default")
    }

    @Test("agent trims skill identifiers") func agentTrimmedSkills() throws {
        let source = agentBase.replacingOccurrences(of: "text.normalize", with: "    text.normalize   ")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.skillIDs.map(\.rawValue) == ["text.normalize"])
    }

    @Test("agent rejects missing skills section") func agentMissingSkillsSection() throws {
        let source = agentBase.replacingOccurrences(of: "## Skills\ntext.normalize\n\n", with: "")
        #expect(throws: AgentMarkdownError.missingSkills) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects empty skills section") func agentEmptySkills() throws {
        let source = agentBase.replacingOccurrences(of: "text.normalize", with: "    ")
        #expect(throws: AgentMarkdownError.missingSkills) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects duplicate skill") func agentDuplicateSkill() throws {
        let source = agentBase.replacingOccurrences(of: "text.normalize", with: "    text.normalize\ntext.normalize")
        #expect(throws: AgentMarkdownError.duplicateSkill("text.normalize")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects missing rule") func agentMissingRule() throws {
        let source = agentBase.replacingOccurrences(of: "## Rule\nSelect only from the declared skills.\n", with: "")
        #expect(throws: AgentMarkdownError.missingField("Rule")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects empty rule") func agentEmptyRule() throws {
        let source = agentBase.replacingOccurrences(of: "Select only from the declared skills.", with: "    ")
        #expect(throws: AgentMarkdownError.missingField("Rule")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects duplicate delimiter") func agentDuplicateDelimiter() throws {
        let source = agentBase + "\n---\n"
        #expect(throws: AgentMarkdownError.missingField("front matter")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects malformed front matter") func agentMalformedFrontMatter() throws {
        let source = agentBase.replacingOccurrences(of: "description: Default personal agent.", with: "description Default personal agent.")
        #expect(throws: AgentMarkdownError.missingField("malformed front matter")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects invalid field name") func agentInvalidFieldName() throws {
        let source = agentBase.replacingOccurrences(of: "name: Personal Default Agent", with: "na.me: Personal Default Agent")
        #expect(throws: AgentMarkdownError.missingField("malformed front matter")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects duplicate front matter") func agentDuplicateFrontMatter() throws {
        let source = agentBase.replacingOccurrences(of: "description: Default personal agent.", with: "description: Default personal agent.\ndescription: Again")
        #expect(throws: AgentMarkdownError.missingField("duplicate field: description")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects missing id") func agentMissingID() throws {
        let source = agentBase.replacingOccurrences(of: "id: personal.default\n", with: "")
        #expect(throws: AgentMarkdownError.missingField("id")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects missing name") func agentMissingName() throws {
        let source = agentBase.replacingOccurrences(of: "name: Personal Default Agent\n", with: "")
        #expect(throws: AgentMarkdownError.missingField("name")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects missing version") func agentMissingVersion() throws {
        let source = agentBase.replacingOccurrences(of: "version: 1.0.0\n", with: "")
        #expect(throws: AgentMarkdownError.missingField("version")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects invalid version") func agentInvalidVersion() throws {
        let source = agentBase.replacingOccurrences(of: "version: 1.0.0", with: "version: 1")
        #expect(throws: AgentMarkdownError.invalidVersion("1")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects four component version") func agentFourPartVersion() throws {
        let source = agentBase.replacingOccurrences(of: "version: 1.0.0", with: "version: 1.0.0.0")
        #expect(throws: AgentMarkdownError.invalidVersion("1.0.0.0")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects duplicate skills section") func agentDuplicateSkillsSection() throws {
        let source = agentBase.replacingOccurrences(of: "\n## Rule", with: "\n## Skills\nanother.skill\n\n## Rule")
        #expect(throws: AgentMarkdownError.missingField("duplicate section: Skills")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent rejects duplicate rule section") func agentDuplicateRuleSection() throws {
        let source = agentBase + "\n## Rule\nAnother rule.\n"
        #expect(throws: AgentMarkdownError.missingField("duplicate section: Rule")) {
            try AgentMarkdownParser().parse(source)
        }
    }

    @Test("agent preserves multiline rule") func agentMultilineRule() throws {
        let source = agentBase.replacingOccurrences(of: "Select only from the declared skills.", with: "    Select only from the declared skills.\nNever execute undeclared skills.")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.instructions.contains("Never execute undeclared skills."))
    }

    @Test("agent supports multiple skills deterministically") func agentMultipleSkills() throws {
        let source = agentBase.replacingOccurrences(of: "text.normalize", with: "    text.normalize\nmemory.search\nprovider.verify")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.skillIDs.map(\.rawValue) == ["text.normalize", "memory.search", "provider.verify"])
    }

    @Test("skill parser treats case in identity literally") func skillIdentityCase() throws {
        let source = skillBase.replacingOccurrences(of: "id: text.normalize", with: "id: Text.Normalize")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.id.rawValue == "Text.Normalize")
    }

    @Test("skill parser keeps description fallback stable") func skillDescriptionFallback() throws {
        let source = skillBase.replacingOccurrences(of: "description: Normalize user text.\n", with: "")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.description == "Text Normalize")
    }

    @Test("agent parser keeps description fallback stable") func agentDescriptionFallback() throws {
        let source = agentBase.replacingOccurrences(of: "description: Default personal agent.\n", with: "")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.description == "Personal Default Agent")
    }

    @Test("skill allows hyphenated front matter key") func skillHyphenatedKey() throws {
        let source = skillBase.replacingOccurrences(of: "description:", with: "description-text:")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.description == "Text Normalize")
    }

    @Test("agent allows underscored front matter key") func agentUnderscoredKey() throws {
        let source = agentBase.replacingOccurrences(of: "description:", with: "description_text:")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.description == "Personal Default Agent")
    }

    @Test("skill section matching ignores surrounding whitespace") func skillSectionWhitespace() throws {
        let source = skillBase.replacingOccurrences(of: "## Input", with: "    ## Input   ")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.inputSchema.identifier == "skill.text.normalize.in")
    }

    @Test("agent section matching ignores surrounding whitespace") func agentSectionWhitespace() throws {
        let source = agentBase.replacingOccurrences(of: "## Skills", with: "    ## Skills   ")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.skillIDs.count == 1)
    }

    @Test("skill body ignores non-section prose") func skillBodyProse() throws {
        let source = skillBase.replacingOccurrences(of: "## Input", with: "    Introductory prose.\n\n## Input")
        let value = try SkillMarkdownParser().parse(source)
        #expect(value.inputSchema.identifier == "skill.text.normalize.in")
    }

    @Test("agent body ignores non-section prose") func agentBodyProse() throws {
        let source = agentBase.replacingOccurrences(of: "## Skills", with: "    Introductory prose.\n\n## Skills")
        let value = try AgentMarkdownParser().parse(source)
        #expect(value.skillIDs.count == 1)
    }

    @Test("memory index allRecords is sorted by id") func memoryAllRecordsStable() {
        var index = MemoryIndex()
        let records = ["z", "a", "m", "b"].map {
            MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: $0, provenance: Provenance(source: "test"))
        }
        records.forEach { index.index($0) }
        #expect(index.allRecords().map(\.id.rawValue) == ["a", "b", "m", "z"])
    }

    @Test("memory createdAt sort breaks ties by id") func memoryCreatedTieBreak() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 1_000)
        let values = ["z", "a", "m"].map {
            MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: $0, provenance: Provenance(source: "test"), createdAt: date)
        }
        values.reversed().forEach { index.index($0) }
        let result = index.query(MemoryQuery(sortOrder: .createdAtAscending))
        #expect(result.records.map(\.id.rawValue) == ["a", "m", "z"])
    }

    @Test("memory descending createdAt also breaks ties by id") func memoryCreatedDescendingTieBreak() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 2_000)
        ["z", "a", "m"].forEach {
            index.index(MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: $0, provenance: Provenance(source: "test"), createdAt: date))
        }
        let result = index.query(MemoryQuery(sortOrder: .createdAtDescending))
        #expect(result.records.map(\.id.rawValue) == ["a", "m", "z"])
    }

    @Test("memory importance sort breaks equal importance by date then id") func memoryImportanceTieBreak() {
        var index = MemoryIndex()
        let first = Date(timeIntervalSince1970: 3_000)
        let second = Date(timeIntervalSince1970: 4_000)
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "z"), kind: .fact, content: "z", provenance: Provenance(source: "test"), createdAt: first, importance: 0.8))
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "b"), kind: .fact, content: "b", provenance: Provenance(source: "test"), createdAt: second, importance: 0.8))
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "a"), kind: .fact, content: "a", provenance: Provenance(source: "test"), createdAt: second, importance: 0.8))
        let result = index.query(MemoryQuery(sortOrder: .importanceDescending))
        #expect(result.records.map(\.id.rawValue) == ["a", "b", "z"])
    }

    @Test("memory relevance sort breaks complete ties by id") func memoryRelevanceTieBreak() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 5_000)
        ["z", "a", "m"].forEach {
            index.index(MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: "shared token", provenance: Provenance(source: "test"), createdAt: date, importance: 0.5))
        }
        let result = index.query(MemoryQuery(textSearch: "shared", sortOrder: .relevance))
        #expect(result.records.map(\.id.rawValue) == ["a", "m", "z"])
    }

    @Test("memory relevance without text is deterministic") func memoryImportanceFallbackTieBreak() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 6_000)
        ["z", "a", "m"].forEach {
            index.index(MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: "same", provenance: Provenance(source: "test"), createdAt: date, importance: 0.5)
        }
        let result = index.query(MemoryQuery(sortOrder: .relevance))
        #expect(result.records.map(\.id.rawValue) == ["a", "m", "z"])
    }

    @Test("memory update preserves deterministic ordering") func memoryUpdateOrdering() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 7_000)
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "b"), kind: .fact, content: "old", provenance: Provenance(source: "test"), createdAt: date))
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "a"), kind: .fact, content: "new", provenance: Provenance(source: "test"), createdAt: date))
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "b"), kind: .fact, content: "updated", provenance: Provenance(source: "test"), createdAt: date))
        #expect(index.allRecords().map(\.id.rawValue) == ["a", "b"])
        #expect(index.record(for: MemoryRecordID(rawValue: "b"))?.content == "updated")
    }

    @Test("memory remove deletes record") func memoryRemoveRecord() {
        var index = MemoryIndex()
        let record = MemoryRecord(id: MemoryRecordID(rawValue: "remove-me"), kind: .fact, content: "remove token", provenance: Provenance(source: "test"))
        index.index(record)
        index.remove(id: record.id)
        #expect(index.count == 0)
        #expect(index.record(for: record.id) == nil)
        #expect(index.allRecords().isEmpty)
    }

    @Test("memory clear resets every observable collection") func memoryClear() {
        var index = MemoryIndex()
        let record = MemoryRecord(id: MemoryRecordID(rawValue: "clear-me"), kind: .fact, content: "clear token", provenance: Provenance(source: "test"), metadata: ["k": "v"])
        index.index(record)
        index.clear()
        #expect(index.count == 0)
        #expect(index.count(scope: nil) == 0)
        #expect(index.allRecords().isEmpty)
        #expect(index.query(MemoryQuery(textSearch: "clear")).records.isEmpty)
    }

    @Test("memory direct id query keeps deterministic requested order under tie") func memoryDirectIDs() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 8_000)
        ["c", "a", "b"].forEach {
            index.index(MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: "same", provenance: Provenance(source: "test"), createdAt: date))
        }
        let query = MemoryQuery(ids: Set([MemoryRecordID(rawValue: "b"), MemoryRecordID(rawValue: "a"), MemoryRecordID(rawValue: "c")]), sortOrder: .createdAtAscending)
        let result = index.query(query)
        #expect(result.records.map(\.id.rawValue) == ["a", "b", "c"])
    }

    @Test("memory limit is applied after deterministic ordering") func memoryLimitAfterTieBreak() {
        var index = MemoryIndex()
        let date = Date(timeIntervalSince1970: 9_000)
        ["z", "a", "m", "b"].forEach {
            index.index(MemoryRecord(id: MemoryRecordID(rawValue: $0), kind: .fact, content: "limit token", provenance: Provenance(source: "test"), createdAt: date))
        }
        let result = index.query(MemoryQuery(textSearch: "limit", sortOrder: .createdAtAscending, limit: 2))
        #expect(result.records.map(\.id.rawValue) == ["a", "b"])
    }

    @Test("memory text matching remains exact token based") func memoryExactToken() {
        var index = MemoryIndex()
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "x"), kind: .fact, content: "computing", provenance: Provenance(source: "test")))
        #expect(index.query(MemoryQuery(textSearch: "comput")).records.isEmpty)
        #expect(index.query(MemoryQuery(textSearch: "computing")).records.count == 1)
    }

    @Test("memory metadata filtering remains exact") func memoryMetadataExact() {
        var index = MemoryIndex()
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "home"), kind: .fact, content: "coffee", provenance: Provenance(source: "test"), metadata: ["place": "home"]))
        index.index(MemoryRecord(id: MemoryRecordID(rawValue: "work"), kind: .fact, content: "coffee", provenance: Provenance(source: "test"), metadata: ["place": "work"]))
        let result = index.query(MemoryQuery(metadataFilters: ["place": "home"]))
        #expect(result.records.map(\.id.rawValue) == ["home"])
    }
}
