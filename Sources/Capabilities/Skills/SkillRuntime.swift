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
    public func register(_ executor: any SkillExecutor, for key: String) { executors[key] = executor }
    public func resolve(_ manifest: SkillManifest) throws -> any SkillExecutor {
        let key = manifest.metadata["executor"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? manifest.metadata["executor"]!
            : manifest.id.rawValue
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
    public init(manifests: [SkillManifest] = []) { for manifest in manifests { self.manifests[manifest.id] = manifest } }
    public func register(_ manifest: SkillManifest) { manifests[manifest.id] = manifest }
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
    public func select(goalStatement: String, available: [SkillManifest]) async throws -> SkillID? {
        let goalTokens = Set(goalStatement.lowercased().split(separator: " ").map(String.init))
        return available.map { manifest in
            let words = Set((manifest.id.rawValue + " " + manifest.name + " " + manifest.description).lowercased().split(separator: " ").map(String.init))
            return (manifest, goalTokens.intersection(words).count)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.first?.0.id
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
        let scoped = allowedSkillIDs.map { ids in available.filter { ids.contains($0.id) } } ?? available
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
        guard !inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SkillRuntimeError.invalidInput(id) }
        let decision = await policy.evaluate(ActionIntent(capabilities: manifest.requiredCapabilities, summary: "Execute skill \(manifest.id.rawValue): \(manifest.description)"))
        guard decision.allowed else {
            if decision.requiresApproval { throw SkillRuntimeError.policyRequiresApproval(decision.reason) }
            throw SkillRuntimeError.policyDenied(decision.reason)
        }
        let executor = try await executors.resolve(manifest)
        return try await executor.execute(manifest: manifest, inputJSON: inputJSON)
    }
    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        let manifest = try await store.load(id: id)
        let executor = try await executors.resolve(manifest)
        return try await executor.verify(manifest: manifest, outputJSON: outputJSON)
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