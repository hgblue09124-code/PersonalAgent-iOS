import Foundation
import PAKernel

public struct AgentManifest: Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let version: SemanticVersion
    public let skillIDs: [SkillID]
    public let instructions: String

    public init(
        id: String,
        name: String,
        description: String,
        version: SemanticVersion,
        skillIDs: [SkillID],
        instructions: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.skillIDs = skillIDs
        self.instructions = instructions
    }
}

public enum AgentMarkdownError: Error, Sendable, Equatable {
    case missingField(String)
    case invalidVersion(String)
    case missingSkills
    case duplicateSkill(String)
    case unknownAgent(String)
}

public struct AgentMarkdownParser: Sendable {
    public init() {}

    public func parse(_ markdown: String) throws -> AgentManifest {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else { throw AgentMarkdownError.missingField("front matter") }

        var fields: [String: String] = [:]
        for line in parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true) {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { throw AgentMarkdownError.missingField("malformed front matter") }
            let key = pieces[0].trimmingCharacters(in: .whitespaces)
            let value = pieces[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { throw AgentMarkdownError.missingField("malformed front matter") }
            guard fields[key] == nil else { throw AgentMarkdownError.missingField("duplicate field: \\(key)") }
            fields[key] = value
        }

        guard let id = fields["id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { throw AgentMarkdownError.missingField("id") }
        guard let name = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw AgentMarkdownError.missingField("name") }
        guard let versionText = fields["version"]?.trimmingCharacters(in: .whitespacesAndNewlines), !versionText.isEmpty else {
            throw AgentMarkdownError.missingField("version")
        }
        guard let version = parseVersion(versionText) else {
            throw AgentMarkdownError.invalidVersion(versionText)
        }

        let body = parts.dropFirst().joined(separator: "\n---\n")
        let skillsText = section(named: "Skills", in: body) ?? ""
        let skillIDs = skillsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { SkillID(rawValue: $0) }
        guard !skillIDs.isEmpty else { throw AgentMarkdownError.missingSkills }

        var seen = Set<SkillID>()
        for skillID in skillIDs {
            guard seen.insert(skillID).inserted else {
                throw AgentMarkdownError.duplicateSkill(skillID.rawValue)
            }
        }

        guard let ruleSection = section(named: "Rule", in: body),
              !ruleSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentMarkdownError.missingField("Rule")
        }
        let rule = ruleSection.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentManifest(
            id: id,
            name: name,
            description: fields["description"] ?? name,
            version: version,
            skillIDs: skillIDs,
            instructions: rule
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

public actor FileAgentStore: Sendable {
    private let directoryURL: URL
    private let parser: AgentMarkdownParser

    public init(directoryURL: URL, parser: AgentMarkdownParser = AgentMarkdownParser()) {
        self.directoryURL = directoryURL
        self.parser = parser
    }

    public func ensureDefaultAgent() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("personal.default.Agent.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.defaultAgentMarkdown.write(to: url, atomically: true, encoding: .utf8)
    }

    public func discover(query: String = "") throws -> [AgentManifest] {
        let values = try loadAll()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return values.sorted { $0.id < $1.id } }
        return values.filter {
            $0.id.lowercased().contains(needle) ||
            $0.name.lowercased().contains(needle) ||
            $0.description.lowercased().contains(needle)
        }.sorted { $0.id < $1.id }
    }

    public func load(id: String) throws -> AgentManifest {
        guard let manifest = try loadAll().first(where: { $0.id == id }) else {
            throw AgentMarkdownError.unknownAgent(id)
        }
        return manifest
    }

    private static let defaultAgentMarkdown = """
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

    private func loadAll() throws -> [AgentManifest] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "md" }
        return try urls.map { try parser.parse(String(contentsOf: $0, encoding: .utf8)) }
    }
}

