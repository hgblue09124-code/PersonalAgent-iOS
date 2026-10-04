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

public actor InMemorySkillStore: SkillStore {
    private var manifests: [SkillID: SkillManifest] = [:]
    public init(manifests: [SkillManifest] = []) {
        for manifest in manifests { self.manifests[manifest.id] = manifest }
    }
    public func register(_ manifest: SkillManifest) { manifests[manifest.id] = manifest }
    public func discover(query: String) async throws -> [SkillManifest] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(manifests.values).sorted { $0.id.rawValue < $1.id.rawValue } }
        return manifests.values.filter {
            $0.id.rawValue.lowercased().contains(needle) ||
            $0.name.lowercased().contains(needle) ||
            $0.description.lowercased().contains(needle)
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
        let goal = goalStatement.lowercased()
        let goalTokens = Set(goal.split(separator: " ").map(String.init))
        return available.map { manifest in
            let words = Set((manifest.id.rawValue + " " + manifest.name + " " + manifest.description).lowercased().split(separator: " ").map(String.init))
            return (manifest, goalTokens.intersection(words).count)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.first?.0.id
    }
}

public actor SkillRuntime: SkillExecuting, SkillVerifying {
    private let store: any SkillStore
    private let selector: any SkillSelecting

    public init(
        store: any SkillStore = InMemorySkillStore(manifests: [SkillRuntime.normalizationManifest]),
        selector: any SkillSelecting = KeywordSkillSelector()
    ) {
        self.store = store
        self.selector = selector
    }

    public func discover(query: String = "") async throws -> [SkillManifest] {
        try await store.discover(query: query)
    }

    public func select(goalStatement: String) async throws -> SkillID {
        let available = try await store.discover(query: "")
        guard let selected = try await selector.select(goalStatement: goalStatement, available: available) else {
            throw SkillRuntimeError.noSelection
        }
        return selected
    }

    public func execute(id: SkillID, inputJSON: String, policy _: any PolicyEvaluating) async throws -> String {
        let manifest = try await store.load(id: id)
        guard !inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillRuntimeError.invalidInput(id)
        }
        guard id == Self.normalizationManifest.id else { throw SkillRuntimeError.unknownSkill(id) }

        let decision = await policy.evaluate(
            ActionIntent(
                capabilities: manifest.requiredCapabilities,
                summary: "Execute skill \(manifest.id.rawValue): \(manifest.description)"
            )
        )
        guard decision.allowed else {
            if decision.requiresApproval {
                throw SkillRuntimeError.policyRequiresApproval(decision.reason)
            }
            throw SkillRuntimeError.policyDenied(decision.reason)
        }
        guard let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              let text = fields["text"] as? String else {
            throw SkillRuntimeError.invalidInput(manifest.id)
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SkillRuntimeError.invalidInput(manifest.id) }
        let output: [String: Any] = ["text": normalized]
        guard let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
              let result = String(data: encoded, encoding: .utf8),
              try await verify(id: id, outputJSON: result) else {
            throw SkillRuntimeError.invalidOutput(manifest.id)
        }
        return result
    }

    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        guard id == Self.normalizationManifest.id,
              let data = outputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              let text = fields["text"] as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
