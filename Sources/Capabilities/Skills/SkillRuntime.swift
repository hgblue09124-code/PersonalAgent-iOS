import Foundation
import PAKernel
import PAModules
import PATools
import PARuntime

public enum SkillRuntimeError: Error, Sendable, Equatable {
    case unknownSkill(SkillID)
    case invalidInput(SkillID)
    case invalidOutput(SkillID)
    case noSelection
    case policyDenied(String)
    case policyRequiresApproval(String)
}

public protocol SkillExecutor: Sendable {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool
}

public actor SkillExecutorRegistry {
    private var executors: [String: any SkillExecutor] = [:]
    public init(executors: [String: any SkillExecutor] = [:]) { self.executors = executors }
    public func register(_ executor: any SkillExecutor, for key: String) {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { return }
        executors[normalizedKey] = executor
    }
    public func resolve(_ manifest: SkillManifest) throws -> any SkillExecutor {
        let configuredKey = manifest.metadata["executor"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if let configuredKey, !configuredKey.isEmpty {
            key = configuredKey
        } else {
            key = manifest.id.rawValue
        }
        guard let executor = executors[key] else { throw SkillRuntimeError.unknownSkill(manifest.id) }
        return executor
    }
}

public struct TextNormalizeSkillExecutor: SkillExecutor {
    public init() {}
    public func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        guard let fields = Self.object(from: inputJSON), let text = fields["text"] as? String else {
            throw SkillRuntimeError.invalidInput(manifest.id)
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SkillRuntimeError.invalidInput(manifest.id) }
        guard let encoded = try? JSONSerialization.data(withJSONObject: ["text": normalized], options: [.sortedKeys]),
              let result = String(data: encoded, encoding: .utf8) else {
            throw SkillRuntimeError.invalidOutput(manifest.id)
        }
        return result
    }
    public func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        guard let fields = Self.object(from: outputJSON), let text = fields["text"] as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func object(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else { return nil }
        return fields
    }
}

public actor InMemorySkillStore: SkillStore {
    private var manifests: [SkillID: SkillManifest] = [:]
    public init(manifests: [SkillManifest] = []) {
        for manifest in manifests {
            let id = SkillID(rawValue: manifest.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !id.rawValue.isEmpty else { continue }
            self.manifests[id] = manifest
        }
    }
    public func register(_ manifest: SkillManifest) {
        let normalizedID = SkillID(rawValue: manifest.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedID.rawValue.isEmpty else { return }
        manifests[normalizedID] = manifest
    }
    public func discover(query: String) async throws -> [SkillManifest] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(manifests.values).sorted { $0.id.rawValue < $1.id.rawValue } }
        return manifests.values.filter {
            $0.id.rawValue.lowercased().contains(needle) || $0.name.lowercased().contains(needle) || $0.description.lowercased().contains(needle)
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }
    public func load(id: SkillID) async throws -> SkillManifest {
        guard let manifest = manifests[id] else { throw SkillRuntimeError.unknownSkill(id) }
        return manifest
    }
}

public struct KeywordSkillSelector: SkillSelecting, Sendable {
    public init() {}

    private static func tokens(_ value: String) -> [String] {
        value.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func containsTokenSequence(_ value: String, _ phrase: String) -> Bool {
        let haystack = tokens(value)
        let needle = tokens(phrase)
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return haystack.indices.contains { index in
            let end = index + needle.count
            guard end <= haystack.count else { return false }
            return Array(haystack[index..<end]) == needle
        }
    }
    public func select(goalStatement: String, available: [SkillManifest]) async throws -> SkillID? {
        let normalizedGoal = goalStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedGoal.isEmpty else { return nil }
        let goalTokens = Set(Self.tokens(normalizedGoal))
        return available.map { manifest in
            let normalizedGoalLowercased = normalizedGoal.lowercased()
            let id = manifest.id.rawValue.lowercased()
            let name = manifest.name.lowercased()
            let searchableText = id + " " + name + " " + manifest.description
            let words = Set(Self.tokens(searchableText))
            let score = goalTokens.intersection(words).count
            let coverage = words.isEmpty ? 0.0 : Double(score) / Double(max(1, words.count))
            let exactMatch = Self.containsTokenSequence(normalizedGoalLowercased, id) || Self.containsTokenSequence(normalizedGoalLowercased, name)
            return (manifest, score, exactMatch, coverage)
        }
        .filter { $0.2 || ($0.1 >= 2 && $0.3 >= 0.20) }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.3 != $1.3 { return $0.3 > $1.3 }
            if $0.2 != $1.2 { return $0.2 && !$1.2 }
            return $0.0.id.rawValue < $1.0.id.rawValue
        }
        .first?.0.id
    }
}

public actor SkillRuntime: SkillExecuting, SkillVerifying {
    private let store: any SkillStore
    private let selector: any SkillSelecting
    private let executors: SkillExecutorRegistry

    public init(
        store: any SkillStore = InMemorySkillStore(manifests: [SkillRuntime.normalizationManifest]),
        selector: any SkillSelecting = KeywordSkillSelector(),
        executors: SkillExecutorRegistry? = nil
    ) {
        self.store = store
        self.selector = selector
        self.executors = executors ?? SkillExecutorRegistry(
            executors: ["text.normalize": TextNormalizeSkillExecutor()]
        )
    }
    public func discover(query: String = "") async throws -> [SkillManifest] { try await store.discover(query: query) }
    public func select(goalStatement: String) async throws -> SkillID {
        try await select(goalStatement: goalStatement, allowedSkillIDs: nil)
    }

    public func select(
        goalStatement: String,
        allowedSkillIDs: Set<SkillID>?
    ) async throws -> SkillID {
        let available = try await store.discover(query: "")
        var seen = Set<SkillID>()
        let unique = available.filter { seen.insert($0.id).inserted }
        let scoped = allowedSkillIDs.map { ids in unique.filter { ids.contains($0.id) } } ?? unique
        guard let selected = try await selector.select(goalStatement: goalStatement, available: scoped) else {
            throw SkillRuntimeError.noSelection
        }
        guard allowedSkillIDs?.contains(selected) ?? true else {
            throw SkillRuntimeError.noSelection
        }
        return selected
    }
    public func execute(id: SkillID, inputJSON: String, policy: any PolicyEvaluating) async throws -> String {
        let manifest = try await store.load(id: id)
        let normalizedInput = inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInput.isEmpty else { throw SkillRuntimeError.invalidInput(id) }
        let decision = await policy.evaluate(ActionIntent(capabilities: manifest.requiredCapabilities, summary: "Execute skill \(manifest.id.rawValue): \(manifest.description)"))
        guard decision.allowed else {
            if decision.requiresApproval { throw SkillRuntimeError.policyRequiresApproval(decision.reason) }
            throw SkillRuntimeError.policyDenied(decision.reason)
        }
        let executor = try await executors.resolve(manifest)
        return try await executor.execute(manifest: manifest, inputJSON: normalizedInput)
    }
    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        let manifest = try await store.load(id: id)
        let normalizedOutput = outputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOutput.isEmpty else { return false }
        let executor = try await executors.resolve(manifest)
        return try await executor.verify(manifest: manifest, outputJSON: normalizedOutput)
    }
    public static let normalizationManifest = SkillManifest(
        id: SkillID(rawValue: "text.normalize"),
        name: "Text Normalize",
        description: "Normalize user text by trimming surrounding whitespace.",
        version: SemanticVersion(major: 1, minor: 0, patch: 0),
        instructions: "Accept {text: string}; return normalized {text: string}.",
        inputSchema: SchemaDocument(identifier: "skill.text.normalize.in"),
        outputSchema: SchemaDocument(identifier: "skill.text.normalize.out"),
        requiredCapabilities: [.read, .execute]
    )
}