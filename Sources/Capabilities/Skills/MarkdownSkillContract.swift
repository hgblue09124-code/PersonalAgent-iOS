import Foundation

public struct SkillDefinition: Sendable, Equatable {
    public let identity: String
    public let scope: String
    public let input: String
    public let rule: String
    public let output: String
    public let permissions: [String]
    public let dependencies: [String]
    public let version: String

    public init(identity: String, scope: String, input: String, rule: String, output: String, permissions: [String], dependencies: [String], version: String) {
        self.identity = identity
        self.scope = scope
        self.input = input
        self.rule = rule
        self.output = output
        self.permissions = permissions
        self.dependencies = dependencies
        self.version = version
    }
}

public enum SkillDefinitionError: Error, Sendable, Equatable {
    case malformed
    case missingField(String)
}

public enum LegacySkillDefinitionParser {
    public static func parse(_ markdown: String) throws -> SkillDefinition {
        var fields: [String: String] = [:]
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { throw SkillDefinitionError.malformed }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty, fields[key] == nil else {
                throw SkillDefinitionError.malformed
            }
            fields[key] = value
        }
        func required(_ key: String) throws -> String {
            guard let value = fields[key], !value.isEmpty else { throw SkillDefinitionError.missingField(key) }
            return value
        }
        func list(_ key: String) throws -> [String] {
            let values = try required(key)
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { String($0) }
            guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
                throw SkillDefinitionError.malformed
            }
            return values
        }
        return SkillDefinition(
            identity: try required("identity"),
            scope: try required("scope"),
            input: try required("input"),
            rule: try required("rule"),
            output: try required("output"),
            permissions: try list("permissions"),
            dependencies: try list("dependencies"),
            version: try required("version")
        )
    }
}
