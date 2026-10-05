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
            guard pieces.count == 2 else { continue }
            fields[pieces[0].trimmingCharacters(in: .whitespaces)] =
                pieces[1].trimmingCharacters(in: .whitespaces)
        }

        guard let id = fields["id"], !id.isEmpty else { throw AgentMarkdownError.missingField("id") }
        guard let name = fields["name"], !name.isEmpty else { throw AgentMarkdownError.missingField("name") }
        guard let versionText = fields["version"], !versionText.isEmpty else {
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

        let rule = section(named: "Rule", in: body)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

public actor FileAgentStore: Sendable {
    private let directoryURL: URL
    private let parser: AgentMarkdownParser

    public init(directoryURL: URL, parser: AgentMarkdownParser = AgentMarkdownParser()) {
        self.directoryURL = directoryURL
        self.parser = parser
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

    private func loadAll() throws -> [AgentManifest] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "md" }
        return try urls.map { try parser.parse(String(contentsOf: $0, encoding: .utf8)) }
    }
}
