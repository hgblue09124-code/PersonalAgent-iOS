import Foundation
import PAKernel
import PARuntime

public protocol SkillExecutor: Sendable {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool
}

public actor SkillExecutorRegistry: Sendable {
    private var executors: [String: any SkillExecutor]

    public init(executors: [String: any SkillExecutor] = [:]) {
        self.executors = executors
    }

    public func register(_ executor: any SkillExecutor, for skillID: String) {
        executors[skillID] = executor
    }

    public func executor(for skillID: String) -> (any SkillExecutor)? {
        executors[skillID]
    }
}

public actor InMemorySkillStore: SkillStore {
    private let manifests: [SkillID: SkillManifest]

    public init(manifests: [SkillManifest] = []) {
        self.manifests = manifests.reduce(into: [:]) { result, manifest in
            // Duplicate manifest IDs must not trap discovery; first definition wins.
            if result[manifest.id] == nil {
                result[manifest.id] = manifest
            }
        }
    }

    public func discover(query: String) async throws -> [SkillManifest] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return manifests.values
            .filter {
                needle.isEmpty ||
                $0.id.rawValue.lowercased().contains(needle) ||
                $0.name.lowercased().contains(needle) ||
                $0.description.lowercased().contains(needle)
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func load(id: SkillID) async throws -> SkillManifest {
        guard let manifest = manifests[id] else {
            throw SkillExecutionError.unknownSkill(id)
        }
        return manifest
    }
}

public struct TextNormalizeSkillExecutor: SkillExecutor {
    public init() {}

    public func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        guard
            let data = inputJSON.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = object["text"] as? String
        else {
            throw SkillExecutionError.malformedSkill
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let output: [String: String] = ["text": normalized]
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }

    public func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        guard
            let data = outputJSON.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["text"] is String
        else { return false }
        return true
    }
}

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
    case unknownSkill(SkillID)
    case policyDenied(String)
    case policyRequiresApproval(String)
}

public typealias SkillRuntimeError = SkillExecutionError

public struct SkillRuntime: Sendable {
    public typealias ModuleHandler = @Sendable (String) async throws -> String
    private let skills: [String: SkillDefinition]
    private let modules: [String: ModuleHandler]
    private let disabled: Set<String>
    private let store: (any SkillStore)?
    private let executors: SkillExecutorRegistry

    public static let normalizationManifest = SkillManifest(
        id: SkillID(rawValue: "text.normalize"),
        name: "Text Normalize",
        description: "Normalize user text by trimming surrounding whitespace.",
        version: SemanticVersion(major: 1, minor: 0, patch: 0),
        instructions: "Trim surrounding whitespace.",
        inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
        outputSchema: SchemaDocument(identifier: "skill.text.normalize.out"),
        requiredCapabilities: [.read, .execute]
    )

    public init(
        skills: [SkillDefinition] = [],
        modules: [String: ModuleHandler] = [:],
        disabled: Set<String> = [],
        store: (any SkillStore)? = nil,
        executors: SkillExecutorRegistry = SkillExecutorRegistry()
    ) {
        self.skills = skills.reduce(into: [:]) { result, skill in
            // Duplicate identities must not trap runtime initialization; first definition wins.
            if result[skill.identity] == nil {
                result[skill.identity] = skill
            }
        }
        self.modules = modules
        self.disabled = disabled
        self.store = store
        self.executors = executors
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
        var manifests = skills.values
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
        if manifests.isEmpty && needle.isEmpty {
            manifests = [Self.normalizationManifest]
        }
        return manifests
    }

    public func select(goalStatement: String, allowedSkillIDs: Set<SkillID>? = nil) async throws -> SkillID {
        let manifests = try await discover(query: "")
            .filter { allowedSkillIDs?.contains($0.id) ?? true }
        guard !manifests.isEmpty else {
            throw SkillExecutionError.noSelection
        }

        let normalizedGoal = goalStatement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = manifests.first(where: {
            $0.id.rawValue.lowercased() == normalizedGoal
                || $0.name.lowercased() == normalizedGoal
        }) {
            return exact.id
        }

        let goalTokens = Set(
            normalizedGoal
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 }
        )
        if let matched = manifests.first(where: { manifest in
            let nameTokens = Set(
                manifest.name.lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
                    .filter { $0.count > 2 }
            )
            return !nameTokens.isEmpty && nameTokens.isSubset(of: goalTokens)
        }) {
            return matched.id
        }

        throw SkillExecutionError.noSelection
    }

    public func execute(id: SkillID, inputJSON: String, policy: any PolicyEvaluating) async throws -> String {
        if disabled.contains(id.rawValue) {
            throw SkillExecutionError.disabledSkill(id.rawValue)
        }

        let manifest: SkillManifest
        if let store {
            manifest = try await store.load(id: id)
        } else if id == Self.normalizationManifest.id {
            manifest = Self.normalizationManifest
        } else if let definition = skills[id.rawValue] {
            guard !disabled.contains(definition.identity) else {
                throw SkillExecutionError.disabledSkill(definition.identity)
            }
            manifest = SkillManifest(
                id: id,
                name: definition.identity,
                description: definition.scope,
                version: SemanticVersion(major: 0, minor: 0, patch: 0),
                instructions: definition.rule,
                inputSchema: SchemaDocument(identifier: definition.input),
                outputSchema: SchemaDocument(identifier: definition.output),
                requiredCapabilities: [.read, .execute]
            )
        } else {
            throw SkillExecutionError.unknownSkill(id)
        }

        let decision = await policy.evaluate(
            ActionIntent(capabilities: manifest.requiredCapabilities, summary: "Execute skill \(id.rawValue)")
        )
        if decision.requiresApproval {
            throw SkillExecutionError.policyRequiresApproval(decision.reason)
        }
        guard decision.allowed else {
            throw SkillExecutionError.policyDenied(decision.reason)
        }

        let executor: any SkillExecutor
        if let registered = await executors.executor(for: id.rawValue) {
            executor = registered
        } else if id == Self.normalizationManifest.id {
            executor = TextNormalizeSkillExecutor()
        } else {
            throw SkillExecutionError.unknownSkill(id)
        }
        return try await executor.execute(manifest: manifest, inputJSON: inputJSON)
    }

    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        if let executor = await executors.executor(for: id.rawValue) {
            let manifest = try await discover(query: "").first(where: { $0.id == id })
                ?? Self.normalizationManifest
            return try await executor.verify(manifest: manifest, outputJSON: outputJSON)
        }

        if id == Self.normalizationManifest.id {
            return try await TextNormalizeSkillExecutor().verify(
                manifest: Self.normalizationManifest,
                outputJSON: outputJSON
            )
        }

        return false
    }
}
