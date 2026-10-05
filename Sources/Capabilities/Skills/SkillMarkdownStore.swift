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

    public func parse(_ markdown: String) throws -> SkillManifest {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else { throw SkillMarkdownError.missingField("front matter") }

        let frontMatter = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = parts.dropFirst().joined(separator: "\n---\n")
        var fields: [String: String] = [:]
        for line in frontMatter.split(separator: "\n", omittingEmptySubsequences: true) {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            fields[pieces[0].trimmingCharacters(in: .whitespaces)] =
                pieces[1].trimmingCharacters(in: .whitespaces)
        }

        guard let id = fields["id"], !id.isEmpty else { throw SkillMarkdownError.missingField("id") }
        guard let name = fields["name"], !name.isEmpty else { throw SkillMarkdownError.missingField("name") }
        guard let versionText = fields["version"], !versionText.isEmpty else { throw SkillMarkdownError.missingField("version") }
        guard let version = parseVersion(versionText) else { throw SkillMarkdownError.invalidVersion(versionText) }

        let description = fields["description"] ?? name
        let input = section(named: "Input", in: body) ?? "{}"
        let output = section(named: "Output", in: body) ?? "{}"
        let rule = section(named: "Rule", in: body) ?? ""
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillMarkdownError.missingField("Rule")
        }

        return SkillManifest(
            id: SkillID(rawValue: id),
            name: name,
            description: description,
            version: version,
            instructions: rule.trimmingCharacters(in: .whitespacesAndNewlines),
            inputSchema: SchemaDocument(identifier: input.trimmingCharacters(in: .whitespacesAndNewlines)),
            outputSchema: SchemaDocument(identifier: output.trimmingCharacters(in: .whitespacesAndNewlines)),
            requiredCapabilities: [.read, .execute],
            metadata: ["source": "Skill.md"]
        )
    }

    private func parseVersion(_ value: String) -> SemanticVersion? {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return SemanticVersion(major: parts[0], minor: parts[1], patch: parts[2])
    }

    private func section(named name: String, in body: String) -> String? {
        let marker = "## " + name
        guard let range = body.range(of: marker) else { return nil }
        let remainder = body[range.upperBound...]
        if let next = remainder.range(of: "\n## ") {
            return String(remainder[..<next.lowerBound])
        }
        return String(remainder)
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
        let url = directoryURL.appendingPathComponent("text.normalize.Skill.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.defaultSkillMarkdown.write(to: url, atomically: true, encoding: .utf8)
    }

    public func discover(query: String) async throws -> [SkillManifest] {
        let values = try loadAll()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return values.sorted { $0.id.rawValue < $1.id.rawValue } }
        return values.filter {
            $0.id.rawValue.lowercased().contains(needle) ||
            $0.name.lowercased().contains(needle) ||
            $0.description.lowercased().contains(needle)
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func load(id: SkillID) async throws -> SkillManifest {
        guard let manifest = try loadAll().first(where: { $0.id == id }) else {
            throw SkillRuntimeError.unknownSkill(id)
        }
        return manifest
    }

    private func loadAll() throws -> [SkillManifest] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "md" }
        return try urls.map { try parser.parse(String(contentsOf: $0, encoding: .utf8)) }
    }

    private static let defaultSkillMarkdown = """
    id: text.normalize
    name: Text Normalize
    version: 1.0.0
    description: Normalize user text by trimming surrounding whitespace.
    ---
    ## Input
    skill.text.normalize.in

    ## Output
    skill.text.normalize.out

    ## Rule
    Trim surrounding whitespace.
    """
}
