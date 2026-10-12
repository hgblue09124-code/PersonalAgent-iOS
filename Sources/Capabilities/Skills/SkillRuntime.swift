import Foundation
import PAKernel
import PAModules

public protocol SkillExecutor: Sendable {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool
}

public actor SkillExecutorRegistry: Sendable {
    private var executors: [String: any SkillExecutor]

    public init(executors: [String: any SkillExecutor] = [:]) {
        self.executors = executors
    }

    /// First registration wins so a later/untrusted module cannot silently replace
    /// the implementation authorized for an existing Skill ID.
    public func register(_ executor: any SkillExecutor, for skillID: String) {
        guard executors[skillID] == nil else { return }
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
            let text = object["text"] as? String
        else { return false }
        return text == text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    case verificationFailed(SkillID)
}

public typealias SkillRuntimeError = SkillExecutionError

public struct SkillRuntime: Sendable {
    public typealias ModuleHandler = @Sendable (String) async throws -> String
    private let skills: [String: SkillDefinition]
    private let modules: [String: ModuleHandler]
    private let disabled: Set<String>
    private let store: (any SkillStore)?
    private let executors: SkillExecutorRegistry
    private let moduleRuntime: ModuleRuntime?

    public static func chatInputText(from goalStatement: String) -> String {
        let statement = goalStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = statement.lowercased()
        // File creation uses a colon as part of its command grammar ("with content:").
        // Keep the full command so the allowlisted workspace adapter can parse path and content.
        let fileCommandPrefixes = ["tạo file ", "tạo tệp ", "create file ", "write file "]
        if fileCommandPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return statement
        }
        // For ordinary prompts, an explicit ": " separates instruction from payload.
        if let separator = statement.range(of: ": "),
           !statement[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(statement[separator.upperBound...])
        }
        return statement
    }

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
        executors: SkillExecutorRegistry = SkillExecutorRegistry(),
        moduleRuntime: ModuleRuntime? = nil
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
        self.moduleRuntime = moduleRuntime
    }

    /// Legacy entry point retained for source compatibility, but execution without
    /// an explicit policy is denied. A module handler is executable code, not a grant.
    public func run(_ request: SkillExecutionRequest) async throws -> String {
        throw SkillExecutionError.policyDenied("explicit policy required")
    }

    public func run(
        _ request: SkillExecutionRequest,
        policy: any PolicyEvaluating
    ) async throws -> String {
        guard let skill = skills[request.skillID] else {
            throw SkillExecutionError.missingSkill(request.skillID)
        }
        guard !disabled.contains(skill.identity) else {
            throw SkillExecutionError.disabledSkill(skill.identity)
        }
        guard skill.identity == request.skillID else {
            throw SkillExecutionError.scopeMismatch
        }
        guard let module = modules[request.moduleID] else {
            throw SkillExecutionError.missingModule(request.moduleID)
        }

        let decision = await policy.evaluate(
            ActionIntent(
                capabilities: [.execute],
                summary: "Execute Skill \\(request.skillID) through module \\(request.moduleID)"
            )
        )
        if decision.requiresApproval {
            throw SkillExecutionError.policyRequiresApproval(decision.reason)
        }
        guard decision.allowed else {
            throw SkillExecutionError.policyDenied(decision.reason)
        }
        try Task.checkCancellation()
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
                .filter { !disabled.contains($0.id.rawValue) }
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
        let exactIDMatches = manifests.filter {
            $0.id.rawValue.lowercased() == normalizedGoal
        }
        if exactIDMatches.count == 1 {
            return exactIDMatches[0].id
        }
        if exactIDMatches.count > 1 {
            throw SkillExecutionError.noSelection
        }

        let exactNameMatches = manifests.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedGoal
        }
        if exactNameMatches.count == 1 {
            return exactNameMatches[0].id
        }
        if exactNameMatches.count > 1 {
            throw SkillExecutionError.noSelection
        }

        let goalTokens = Self.intentTokens(normalizedGoal)
        let nameMatches = manifests.compactMap { manifest -> (id: SkillID, tokenCount: Int)? in
            let nameTokens = Self.intentTokens(manifest.name)
            guard !nameTokens.isEmpty, nameTokens.isSubset(of: goalTokens) else { return nil }
            return (id: manifest.id, tokenCount: nameTokens.count)
        }.sorted {
            if $0.tokenCount != $1.tokenCount { return $0.tokenCount > $1.tokenCount }
            return $0.id.rawValue < $1.id.rawValue
        }
        if let best = nameMatches.first {
            if nameMatches.count > 1, best.tokenCount == nameMatches[1].tokenCount {
                throw SkillExecutionError.noSelection
            }
            return best.id
        }

        // Description matching broadens discovery without making uncertain choices:
        // require at least two meaningful overlaps and a unique best score.
        let ranked = manifests.map { manifest -> (id: SkillID, score: Int, overlapCount: Int) in
            let nameTokens = Self.intentTokens(manifest.name)
            let descriptionTokens = Self.intentTokens(manifest.description)
            let nameMatches = goalTokens.intersection(nameTokens).count
            let descriptionMatches = goalTokens.intersection(descriptionTokens).count
            return (
                id: manifest.id,
                score: nameMatches * 3 + descriptionMatches,
                overlapCount: goalTokens.intersection(nameTokens.union(descriptionTokens)).count
            )
        }
        .filter { $0.overlapCount >= 2 && $0.score >= 2 }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id.rawValue < $1.id.rawValue
        }

        guard let best = ranked.first else {
            throw SkillExecutionError.noSelection
        }
        if ranked.count > 1, best.score == ranked[1].score {
            throw SkillExecutionError.noSelection
        }
        return best.id
    }

    private static func intentTokens(_ value: String) -> Set<String> {
        let stopWords: Set<String> = [
            "please", "could", "would", "should", "help", "want", "need",
            "make", "using", "use", "with", "from", "into", "about",
            "this", "that", "these", "those", "your", "you", "the",
            "and", "for", "are", "was", "were", "have", "has", "had",
            "can", "how", "what", "when", "where", "why", "who"
        ]
        return Set(
            value.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    public func execute(
        id: SkillID,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> String {
        try await executeInternal(id: id, inputJSON: inputJSON, policy: policy, verifyOutput: false)
    }

    /// Execute and verify at the runtime boundary for callers that expose results directly.
    /// The same executor instance must execute and verify the result.
    public func executeVerified(
        id: SkillID,
        inputJSON: String,
        policy: any PolicyEvaluating
    ) async throws -> String {
        try await executeInternal(id: id, inputJSON: inputJSON, policy: policy, verifyOutput: true)
    }

    private func executeInternal(
        id: SkillID,
        inputJSON: String,
        policy: any PolicyEvaluating,
        verifyOutput: Bool
    ) async throws -> String {
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

        guard let executor = await resolveExecutor(for: manifest) else {
            throw SkillExecutionError.unknownSkill(id)
        }
        // Cancellation may arrive while policy or executor lookup is suspended.
        // Re-check at the last boundary before invoking capability code.
        try Task.checkCancellation()
        let output = try await executor.execute(manifest: manifest, inputJSON: inputJSON)
        // Executors may suspend without cooperating with cancellation. Never return
        // a late result as success after the caller has cancelled the Skill run.
        try Task.checkCancellation()
        if verifyOutput {
            guard try await executor.verify(manifest: manifest, outputJSON: output) else {
                throw SkillExecutionError.verificationFailed(id)
            }
            try Task.checkCancellation()
        }
        return output
    }

    private func manifestForVerification(id: SkillID) async throws -> SkillManifest {
        if let store {
            return try await store.load(id: id)
        }
        if id == Self.normalizationManifest.id {
            return Self.normalizationManifest
        }
        if let definition = skills[id.rawValue] {
            return SkillManifest(
                id: id,
                name: definition.identity,
                description: definition.scope,
                version: SemanticVersion(major: 0, minor: 0, patch: 0),
                instructions: definition.rule,
                inputSchema: SchemaDocument(identifier: definition.input),
                outputSchema: SchemaDocument(identifier: definition.output),
                requiredCapabilities: [.read, .execute]
            )
        }
        throw SkillExecutionError.unknownSkill(id)
    }

    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        guard !disabled.contains(id.rawValue) else { return false }
        let manifest = try await manifestForVerification(id: id)
        guard let executor = await resolveExecutor(for: manifest) else { return false }
        return try await executor.verify(manifest: manifest, outputJSON: outputJSON)
    }

    private func resolveExecutor(for manifest: SkillManifest) async -> (any SkillExecutor)? {
        if let registered = await executors.executor(for: manifest.id.rawValue) {
            return registered
        }
        // Skill.md's executor field is declarative, not executable code. Resolve
        // only the built-in executor here; arbitrary names must never instantiate
        // or authorize an implementation by themselves.
        if manifest.metadata["executor"] == "text.normalize"
            || manifest.id == Self.normalizationManifest.id {
            return TextNormalizeSkillExecutor()
        }
        if let moduleID = manifest.metadata["moduleID"],
           !moduleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let moduleRuntime {
            return ModuleBackedSkillExecutor(moduleRuntime: moduleRuntime, moduleID: ModuleID(rawValue: moduleID))
        }
        return nil
    }
}

private struct ModuleBackedSkillExecutor: SkillExecutor {
    let moduleRuntime: ModuleRuntime
    let moduleID: ModuleID

    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        let contract = try await matchingContract(for: manifest)
        guard let data = inputJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillExecutionError.malformedSkill
        }
        var fields: [String: String] = [:]
        if let adapter = manifest.metadata["chatInputAdapter"] {
            guard Set(object.keys) == ["text"],
                  let rawText = object["text"] as? String else {
                throw SkillExecutionError.malformedSkill
            }
            let argumentsObject: [String: String]
            switch adapter {
            case "workspace.search":
                // Skill.md cannot select arbitrary code or operations by naming an adapter.
                guard moduleID.rawValue == "tool.workspace.read" else {
                    throw SkillExecutionError.malformedSkill
                }
                let query = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, query.count <= 256 else {
                    throw SkillExecutionError.malformedSkill
                }
                argumentsObject = ["operation": "search", "query": query]
            case "workspace.create-file":
                guard moduleID.rawValue == "tool.workspace.write",
                      let request = Self.parseCreateFileRequest(rawText) else {
                    throw SkillExecutionError.malformedSkill
                }
                argumentsObject = [
                    "operation": "write",
                    "path": request.path,
                    "content": request.content
                ]
            default:
                // Adapters are allowlisted executable code, not dynamic Skill instructions.
                throw SkillExecutionError.malformedSkill
            }
            let arguments = try JSONSerialization.data(withJSONObject: argumentsObject, options: [.sortedKeys])
            fields["arguments"] = String(decoding: arguments, as: UTF8.self)
        } else {
            for (key, value) in object {
                if let string = value as? String {
                    fields[key] = string
                } else {
                    let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
                    fields[key] = String(decoding: encoded, as: UTF8.self)
                }
            }
        }
        let result = try await moduleRuntime.execute(
            ModuleInvocation(moduleID: moduleID, input: ModulePayload(schema: contract.inputSchema, fields: fields))
        )
        let encoded = try JSONSerialization.data(withJSONObject: result.output.fields, options: [.sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }

    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        guard (try? await matchingContract(for: manifest)) != nil,
              let data = outputJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: String] else {
            return false
        }
        return true
    }

    private func matchingContract(for manifest: SkillManifest) async throws -> ModuleContract {
        guard let contract = await moduleRuntime.contracts().first(where: { $0.id == moduleID }) else {
            throw SkillExecutionError.missingModule(moduleID.rawValue)
        }
        guard contract.inputSchema.identifier == manifest.inputSchema.identifier,
              contract.outputSchema.identifier == manifest.outputSchema.identifier else {
            throw SkillExecutionError.malformedSkill
        }
        return contract
    }

    private static func parseCreateFileRequest(_ rawText: String) -> (path: String, content: String)? {
        let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["tạo file ", "tạo tệp ", "create file ", "write file "]
        guard let prefix = prefixes.first(where: { normalized.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let remainder = String(normalized.dropFirst(prefix.count))
        let delimiters = [" với nội dung:", " with content:", "\nnội dung:", "\ncontent:"]
        guard let delimiter = delimiters.compactMap({ candidate -> (Range<String.Index>, String)? in
            guard let range = remainder.range(of: candidate, options: [.caseInsensitive]) else { return nil }
            return (range, candidate)
        }).first else {
            return nil
        }
        let rawPath = String(remainder[..<delimiter.0.lowerBound])
        let path = rawPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\\\"'")))
        let content = String(remainder[delimiter.0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !content.isEmpty else { return nil }
        return (path, content)
    }
}
