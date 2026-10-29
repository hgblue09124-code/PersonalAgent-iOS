import Foundation
import PAKernel

public enum SkillMarkdownError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidVersion(String)
    case invalidSchema(String)
}

/// Parses the deliberately small Skill.md contract.
/// Front matter supplies identity; sections supply the grammar and the single rule.
public struct SkillMarkdownParser: Sendable {
    public init() {}

    public static func parse(_ markdown: String) throws -> SkillDefinition {
        try LegacySkillDefinitionParser.parse(markdown)
    }

    public func parse(_ markdown: String) throws -> SkillManifest {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n---\n")
        guard parts.count == 2, !normalized.hasPrefix("---\n") else { throw SkillMarkdownError.invalidSchema("expected exactly one document delimiter") }

        let frontMatter = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = parts.dropFirst().joined(separator: "\n---\n")
        var fields: [String: String] = [:]
        for line in frontMatter.split(separator: "\n", omittingEmptySubsequences: true) {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { throw SkillMarkdownError.missingField("malformed front matter") }
            let key = pieces[0].trimmingCharacters(in: .whitespaces)
            let value = pieces[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { throw SkillMarkdownError.missingField("malformed front matter") }
            guard key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { throw SkillMarkdownError.invalidSchema("invalid field name: \(key)") }
            guard fields[key] == nil else { throw SkillMarkdownError.missingField("duplicate field: \(key)") }
            fields[key] = value
        }

        guard let id = fields["id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { throw SkillMarkdownError.missingField("id") }
        guard let name = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw SkillMarkdownError.missingField("name") }
        guard let versionText = fields["version"]?.trimmingCharacters(in: .whitespacesAndNewlines), !versionText.isEmpty else { throw SkillMarkdownError.missingField("version") }
        guard let version = parseVersion(versionText) else { throw SkillMarkdownError.invalidVersion(versionText) }

        let description = fields["description"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? fields["description"]!.trimmingCharacters(in: .whitespacesAndNewlines)
            : name
        guard let input = try section(named: "Input", in: body) else { throw SkillMarkdownError.missingField("Input") }
        guard let output = try section(named: "Output", in: body) else { throw SkillMarkdownError.missingField("Output") }
        guard let rule = try section(named: "Rule", in: body) else { throw SkillMarkdownError.missingField("Rule") }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillMarkdownError.missingField("Input")
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillMarkdownError.missingField("Output")
        }
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillMarkdownError.missingField("Rule")
        }

        return SkillManifest(
            id: SkillID(rawValue: id.trimmingCharacters(in: .whitespacesAndNewlines)),
            name: name,
            description: description,
            version: version,
            instructions: rule.trimmingCharacters(in: .whitespacesAndNewlines),
            inputSchema: try makeSchemaDocument(
                identifier: input.trimmingCharacters(in: .whitespacesAndNewlines),
                rawJSON: fields["inputSchemaJSON"],
                field: "inputSchemaJSON"
            ),
            outputSchema: try makeSchemaDocument(
                identifier: output.trimmingCharacters(in: .whitespacesAndNewlines),
                rawJSON: fields["outputSchemaJSON"],
                field: "outputSchemaJSON"
            ),
            requiredCapabilities: [.read, .execute],
            metadata: {
                var metadata = [
                    "source": "Skill.md",
                    "executor": fields["executor"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? fields["executor"]!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : id
                ]
                if let moduleID = fields["moduleID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !moduleID.isEmpty {
                    metadata["moduleID"] = moduleID
                }
                if let adapter = fields["chatInputAdapter"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !adapter.isEmpty {
                    metadata["chatInputAdapter"] = adapter
                }
                return metadata
            }()
        )
    }

    /// Optional front-matter schemas add structural validation without changing the
    /// existing Input/Output section identifiers used by Module contracts.
    private func makeSchemaDocument(
        identifier: String,
        rawJSON: String?,
        field: String
    ) throws -> SchemaDocument {
        guard let rawJSON else { return SchemaDocument(identifier: identifier) }
        guard let data = rawJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else {
            throw SkillMarkdownError.invalidSchema("invalid JSON object in \(field)")
        }
        let canonicalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return SchemaDocument(identifier: identifier, rawJSON: String(decoding: canonicalData, as: UTF8.self))
    }

    private func parseVersion(_ value: String) -> SemanticVersion? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    private func section(named name: String, in body: String) throws -> String? {
        let marker = "## " + name
        let lines = body.components(separatedBy: "\n")
        let matches = lines.indices.filter {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == marker
        }
        guard matches.count <= 1 else {
            throw SkillMarkdownError.missingField("duplicate section: \(name)")
        }
        guard let index = matches.first else { return nil }
        let start = index + 1
        let end = lines[start...].firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
        } ?? lines.count
        return lines[start..<end].joined(separator: "\n")
    }
}

public actor FileSkillStore: SkillStore {
    private let directoryURL: URL
    private let parser: SkillMarkdownParser

    public init(directoryURL: URL, parser: SkillMarkdownParser = SkillMarkdownParser()) {
        self.directoryURL = directoryURL
        self.parser = parser
    }

    public func ensureDefaultSkill() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let normalizeURL = directoryURL.appendingPathComponent("text.normalize.Skill.md")
        if !FileManager.default.fileExists(atPath: normalizeURL.path) {
            try Self.defaultSkillMarkdown.write(to: normalizeURL, atomically: true, encoding: .utf8)
        }

        try ensureWorkspaceSkill(
            at: directoryURL.appendingPathComponent("workspace.create-file.Skill.md"),
            defaultMarkdown: Self.defaultCreateFileSkillMarkdown,
            skillID: "workspace.create-file",
            inputSchemaID: "tool.workspace.write.input",
            outputSchemaID: "tool.workspace.write.output",
            moduleID: "tool.workspace.write",
            adapter: "workspace.create-file"
        )
        try ensureWorkspaceSkill(
            at: directoryURL.appendingPathComponent("workspace.search.Skill.md"),
            defaultMarkdown: Self.defaultSearchSkillMarkdown,
            skillID: "workspace.search",
            inputSchemaID: "tool.workspace.read.input",
            outputSchemaID: "tool.workspace.read.output",
            moduleID: "tool.workspace.read",
            adapter: "workspace.search"
        )
        try ensureWorkspaceSkill(
            at: directoryURL.appendingPathComponent("workspace.read-file.Skill.md"),
            defaultMarkdown: Self.defaultReadFileSkillMarkdown,
            skillID: "workspace.read-file",
            inputSchemaID: "tool.workspace.read.input",
            outputSchemaID: "tool.workspace.read.output",
            moduleID: "tool.workspace.read",
            adapter: "workspace.read-file"
        )
    }

    /// Repairs only missing host-owned bindings on a canonical built-in Skill.
    /// A custom, malformed, schema-mismatched, or conflicting Skill is left untouched.
    private func ensureWorkspaceSkill(
        at url: URL,
        defaultMarkdown: String,
        skillID: String,
        inputSchemaID: String,
        outputSchemaID: String,
        moduleID: String,
        adapter: String
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try defaultMarkdown.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let original = try String(contentsOf: url, encoding: .utf8)
        guard let manifest = try? parser.parse(original),
              manifest.id.rawValue == skillID,
              manifest.inputSchema.identifier == inputSchemaID,
              manifest.outputSchema.identifier == outputSchemaID else {
            return
        }

        let existingModuleID = manifest.metadata["moduleID"]
        let existingAdapter = manifest.metadata["chatInputAdapter"]
        guard (existingModuleID == nil || existingModuleID == moduleID),
              (existingAdapter == nil || existingAdapter == adapter) else {
            return
        }

        var missingFields: [String] = []
        if existingModuleID == nil { missingFields.append("moduleID: \(moduleID)") }
        if existingAdapter == nil { missingFields.append("chatInputAdapter: \(adapter)") }
        guard !missingFields.isEmpty else { return }

        let normalized = original.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        guard let delimiterIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            return
        }
        lines.insert(contentsOf: missingFields, at: delimiterIndex)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public func discover(query: String) async throws -> [SkillManifest] {
        // A malformed, unrelated file must not disable every healthy Skill in the
        // store. Invalid manifests are excluded from discovery and cannot execute.
        let values = try loadAll(ignoringMalformedFiles: true)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return values.sorted { $0.id.rawValue < $1.id.rawValue } }
        return values.filter {
            $0.id.rawValue.lowercased().contains(needle) ||
            $0.name.lowercased().contains(needle) ||
            $0.description.lowercased().contains(needle)
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func load(id: SkillID) async throws -> SkillManifest {
        // Keep failures local to the requested Skill. If its own manifest is malformed,
        // surface that parse failure; malformed sibling files do not poison this lookup.
        guard let manifest = try loadAll(
            ignoringMalformedFiles: true,
            requestedID: id
        ).first(where: { $0.id == id }) else {
            throw SkillExecutionError.unknownSkill(id)
        }
        return manifest
    }

    private func loadAll(
        ignoringMalformedFiles: Bool = false,
        requestedID: SkillID? = nil
    ) throws -> [SkillManifest] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "md" }
        var manifests: [SkillManifest] = []
        var seen = Set<SkillID>()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch let error as CocoaError where error.code == .fileReadInapplicableStringEncoding {
                // Only malformed text encoding is safe to isolate. Do not turn unrelated
                // filesystem failures (permissions, I/O, removed files) into "missing Skills".
                if ignoringMalformedFiles && url.deletingPathExtension().lastPathComponent != requestedID?.rawValue {
                    continue
                }
                throw SkillMarkdownError.invalidSchema("invalid UTF-8: \(url.lastPathComponent)")
            }
            let manifest: SkillManifest
            do {
                manifest = try parser.parse(text)
            } catch {
                if !ignoringMalformedFiles || (requestedID != nil && declaredSkillID(in: text) == requestedID?.rawValue) {
                    throw error
                }
                continue
            }
            guard seen.insert(manifest.id).inserted else {
                // Duplicate valid IDs are ambiguous and remain a store-level error.
                throw SkillMarkdownError.missingField("duplicate skill id: \(manifest.id.rawValue)")
            }
            manifests.append(manifest)
        }
        return manifests
    }

    private func declaredSkillID(in markdown: String) -> String? {
        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let separator = trimmed.firstIndex(of: ":") else { return nil }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "id" else { continue }
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static let defaultSkillMarkdown = """
    id: text.normalize
    name: Text Normalize
    version: 1.0.0
    description: Normalize user text by trimming surrounding whitespace.
    executor: text.normalize
    ---
    ## Input
    skill.text.normalize.in

    ## Output
    skill.text.normalize.out

    ## Rule
    Trim surrounding whitespace.
    """

    private static let defaultCreateFileSkillMarkdown = """
    id: workspace.create-file
    name: Tạo File
    version: 1.0.0
    description: Create file in workspace, write file, tạo tệp trong workspace.
    moduleID: tool.workspace.write
    chatInputAdapter: workspace.create-file
    ---
    ## Input
    tool.workspace.write.input

    ## Output
    tool.workspace.write.output

    ## Rule
    Create a text file only inside the permitted AgentOS workspace. Use the explicit form "Tạo file workspace/notes.md với nội dung: nội dung tệp" or "Create file workspace/notes.md with content: file contents". Never claim success unless the Workspace tool returns verified output.
    """

    private static let defaultSearchSkillMarkdown = """
    id: workspace.search
    name: Tìm kiếm Workspace
    version: 1.0.0
    description: Search workspace text content, find matching files, tìm nội dung trong workspace.
    moduleID: tool.workspace.read
    chatInputAdapter: workspace.search
    ---
    ## Input
    tool.workspace.read.input

    ## Output
    tool.workspace.read.output

    ## Rule
    Search readable text files only within the permitted AgentOS workspace. Never expose protected files or secret-like content. Report only paths returned by the Workspace Read tool.
    """

    private static let defaultReadFileSkillMarkdown = """
    id: workspace.read-file
    name: Read / Đọc File
    version: 1.0.0
    description: Read a named path and return the actual file text, đọc nội dung theo đường dẫn đã chỉ định.
    moduleID: tool.workspace.read
    chatInputAdapter: workspace.read-file
    ---
    ## Input
    tool.workspace.read.input

    ## Output
    tool.workspace.read.output

    ## Rule
    Read only a specifically named readable text file inside the permitted workspace. Never read protected paths or secret-like content. Return the content only when the Workspace Read tool reports a verified read.
    """
}
