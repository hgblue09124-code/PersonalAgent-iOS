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
        guard parts.count == 2 else { throw SkillMarkdownError.invalidSchema("expected exactly one document delimiter") }

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
            guard fields[key] == nil else { throw SkillMarkdownError.missingField("duplicate field: \\(key)") }
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
            inputSchema: SchemaDocument(identifier: input.trimmingCharacters(in: .whitespacesAndNewlines)),
            outputSchema: SchemaDocument(identifier: output.trimmingCharacters(in: .whitespacesAndNewlines)),
            requiredCapabilities: [.read, .execute],
            metadata: [
                "source": "Skill.md",
                "executor": fields["executor"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? fields["executor"]!.trimmingCharacters(in: .whitespacesAndNewlines) : id
            ]
        )
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
        var manifests: [SkillManifest] = []
        var seen = Set<SkillID>()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw SkillMarkdownError.invalidSchema("invalid UTF-8: \(url.lastPathComponent)")
            }
            let manifest = try parser.parse(text)
            guard seen.insert(manifest.id).inserted else {
                throw SkillMarkdownError.missingField("duplicate skill id: \(manifest.id.rawValue)")
            }
            manifests.append(manifest)
        }
        return manifests
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
}
