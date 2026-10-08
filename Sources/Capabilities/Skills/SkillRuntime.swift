import Foundation
import PAKernel
import PARuntime

public struct SkillExecutionRequest: Sendable, Equatable {
    public let skillID: String
    public let moduleID: String
    public let input: String
    public init(skillID: String, moduleID: String, input: String) {
        self.skillID = skillID; self.moduleID = moduleID; self.input = input
    }
}

public enum SkillExecutionError: Error, Sendable, Equatable {
    case missingSkill(String)
    case missingModule(String)
    case disabledSkill(String)
    case malformedSkill
    case scopeMismatch
    case noSelection
}

public typealias SkillRuntimeError = SkillExecutionError

public struct SkillRuntime: Sendable {
    public typealias ModuleHandler = @Sendable (String) async throws -> String
    private let skills: [String: SkillDefinition]
    private let modules: [String: ModuleHandler]
    private let disabled: Set<String>
    private let store: (any SkillStore)?

    public init(
        skills: [SkillDefinition] = [],
        modules: [String: ModuleHandler] = [:],
        disabled: Set<String> = [],
        store: (any SkillStore)? = nil
    ) {
        self.skills = Dictionary(uniqueKeysWithValues: skills.map { ($0.identity, $0) })
        self.modules = modules
        self.disabled = disabled
        self.store = store
    }

    public func run(_ request: SkillExecutionRequest) async throws -> String {
        guard let skill = skills[request.skillID] else { throw SkillExecutionError.missingSkill(request.skillID) }
        guard !disabled.contains(skill.identity) else { throw SkillExecutionError.disabledSkill(skill.identity) }
        guard skill.identity == request.skillID else { throw SkillExecutionError.scopeMismatch }
        guard let module = modules[request.moduleID] else { throw SkillExecutionError.missingModule(request.moduleID) }
        return try await module(request.input)
    }

    public func discover() -> [SkillID] {
        skills.keys
            .filter { !disabled.contains($0) }
            .sorted()
            .map { SkillID(rawValue: $0) }
    }

    public func discover(query: String = "") async throws -> [SkillManifest] {
        if let store {
            return try await store.discover(query: query)
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skills.values
            .filter { needle.isEmpty || $0.identity.lowercased().contains(needle) }
            .sorted { $0.identity < $1.identity }
            .map {
                SkillManifest(
                    id: SkillID(rawValue: $0.identity),
                    name: $0.identity,
                    description: $0.scope,
                    version: SemanticVersion(major: 0, minor: 0, patch: 0),
                    instructions: $0.rule,
                    inputSchema: SchemaDocument(identifier: $0.input),
                    outputSchema: SchemaDocument(identifier: $0.output),
                    requiredCapabilities: [.read, .execute]
                )
            }
    }

    public func select(goalStatement: String, allowedSkillIDs: Set<SkillID>? = nil) async throws -> SkillID {
        let candidates = try await discover(query: "").map { $0.id }.filter { allowedSkillIDs?.contains($0) ?? true }
        guard !candidates.isEmpty else {
            throw SkillExecutionError.noSelection
        }
        let normalizedGoal = goalStatement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let exact = candidates.first(where: { $0.rawValue.lowercased() == normalizedGoal }) else {
            throw SkillExecutionError.noSelection
        }
        return exact
    }

    public func execute(id: SkillID, inputJSON: String, policy: any PolicyEvaluating) async throws -> String {
        _ = policy
        return try await run(
            SkillExecutionRequest(
                skillID: id.rawValue,
                moduleID: id.rawValue,
                input: inputJSON
            )
        )
    }

    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        _ = id
        return !outputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
