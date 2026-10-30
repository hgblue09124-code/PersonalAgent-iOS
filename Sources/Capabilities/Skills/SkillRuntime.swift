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
            manifest.inputSchema.identifier == SkillRuntime.normalizationManifest.inputSchema.identifier,
            manifest.outputSchema.identifier == SkillRuntime.normalizationManifest.outputSchema.identifier,
            let data = inputJSON.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["text"],
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
            manifest.inputSchema.identifier == SkillRuntime.normalizationManifest.inputSchema.identifier,
            manifest.outputSchema.identifier == SkillRuntime.normalizationManifest.outputSchema.identifier,
            let data = outputJSON.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["text"],
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
    case unavailableSkill(SkillID)
    case unknownSkill(SkillID)
    case policyDenied(String)
    case policyRequiresApproval(String)
    case verificationFailed(SkillID)
}

public typealias SkillRuntimeError = SkillExecutionError

/// Reports whether a concrete executor can be resolved. This does not grant capability
/// or bypass policy/approval checks at execution time.
public enum SkillExecutorAvailability: String, Sendable, Equatable {
    case available
    case unavailable
}

public struct SkillRuntime: Sendable {
    public typealias ModuleHandler = @Sendable (String) async throws -> String
    private let skills: [String: SkillDefinition]
    private let modules: [String: ModuleHandler]
    private let disabled: Set<String>
    private let store: (any SkillStore)?
    private let executors: SkillExecutorRegistry
    private let moduleRuntime: ModuleRuntime?

    /// Removes only the explicitly supported conversational lead-ins. Keep this
    /// shared by chat input extraction and deterministic preflight so both stages
    /// classify the same request; this helper does not authorize or execute actions.
    public static func removingConversationalLeadIns(from input: String) -> String {
        let politePrefixes = [
            "hãy ", "vui lòng ", "giúp tôi ", "giúp mình ", "giúp anh ", "làm ơn ", "anh ", "em ",
            "please ", "kindly ", "could you ", "can you ", "would you ", "help me ",
            "i need you to "
        ]
        // Strip whitespace only at the command boundary. Trailing whitespace may
        // belong to a file payload and must survive the Chat -> Skill handoff.
        var command = String(input.drop(while: { $0.isWhitespace }))
        while let lead = politePrefixes.first(where: {
            command.lowercased().hasPrefix($0)
        }) {
            command = String(command.dropFirst(lead.count))
                .drop(while: { $0.isWhitespace })
                .description
        }
        return command
    }

    public static func chatInputText(from goalStatement: String) -> String {
        // Contextual chat input may contain prior turns and memory. The explicit
        // current-request boundary is authoritative; never parse an earlier turn as
        // the active Skill command.
        var payloadStatement = goalStatement
        if let marker = goalStatement.range(of: "Current user request:\n", options: .backwards) {
            payloadStatement = String(goalStatement[marker.upperBound...])
        }
        let statement = String(payloadStatement.drop(while: { $0.isWhitespace }))
        // Keep file-creation commands intact for the allowlisted workspace adapter.
        // Only a supported command receives normalization; ordinary chat remains unchanged.
        let fileCommandPrefixes = [
            "tạo một file ", "tạo một tệp ", "tạo file ", "tạo tệp ",
            "create a file ", "create file ", "write a file ", "write file ",
            "make a file ", "make file "
        ]
        let command = removingConversationalLeadIns(from: statement)
        if fileCommandPrefixes.contains(where: { command.lowercased().hasPrefix($0) }) {
            return command
        }
        // For ordinary prompts, preserve the payload exactly, including trailing whitespace.
        if let separator = payloadStatement.range(of: ": "),
           !payloadStatement[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(payloadStatement[separator.upperBound...])
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

        var goalTokens = Self.intentTokens(normalizedGoal)
        // A direct request such as “Read workspace/notes.md” names a file path
        // without the word “file”. Treat the explicit workspace path as that
        // intent only when the action is already a read, preserving ambiguity guards.
        if goalTokens.contains("read"), normalizedGoal.contains("workspace/") {
            goalTokens.insert("file")
        }
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
            "can", "how", "what", "when", "where", "why", "who",
            "hãy", "vui", "lòng", "giúp", "tôi", "mình", "anh", "em",
            "trong", "trên", "dưới", "với", "cho", "của", "một", "các",
            "những", "và", "là", "để", "này", "đó", "tôi", "bạn"
        ]
        let actionSynonyms: [String: String] = [
            "tìm": "search", "kiếm": "search", "tra": "search", "cứu": "search",
            "đọc": "read", "xem": "read", "mở": "read",
            "tạo": "create", "viết": "create", "soạn": "create",
            "write": "create", "make": "create",
            "tệp": "file"
        ]
        return Set(
            value.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .map { actionSynonyms[$0] ?? $0 }
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
            guard manifest.id == id else {
                throw SkillExecutionError.unknownSkill(id)
            }
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

        // Executing an executor is itself an execution capability. A Skill manifest
        // may request fewer capabilities, but it cannot downgrade the authorization
        // required by the runtime to invoke capability code.
        let executionCapabilities = manifest.requiredCapabilities.union(.execute)
        let decision = await policy.evaluate(
            ActionIntent(skillID: id, capabilities: executionCapabilities, summary: "Execute skill \(id.rawValue)")
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
        try Task.checkCancellation()
        try SkillJSONSchemaValidator.validate(inputJSON: inputJSON, schema: manifest.inputSchema)
        // Cancellation may arrive while policy, executor lookup, or validation is suspended.
        // Re-check at the last boundary before invoking capability code.
        try Task.checkCancellation()
        let output = try await executor.execute(manifest: manifest, inputJSON: inputJSON)
        // Executors may suspend without cooperating with cancellation. Never return
        // a late result as success after the caller has cancelled the Skill run.
        try Task.checkCancellation()
        if verifyOutput {
            // The manifest contract is independent of the executor's own verifier.
            // Never expose output that violates the declared JSON schema, even if
            // a custom executor incorrectly reports that output as verified.
            // Older host-registered executors use the default empty schema for
            // opaque text results. Enforce JSON output contracts when a manifest
            // actually declares constraints; preserve that legacy unconstrained form.
            if manifest.outputSchema.rawJSON.trimmingCharacters(in: .whitespacesAndNewlines) != "{}" {
                do {
                    try SkillJSONSchemaValidator.validate(inputJSON: output, schema: manifest.outputSchema)
                } catch {
                    throw SkillExecutionError.verificationFailed(id)
                }
            }
            guard try await executor.verify(manifest: manifest, outputJSON: output) else {
                throw SkillExecutionError.verificationFailed(id)
            }
            try Task.checkCancellation()
        }
        return output
    }

    private func manifestForVerification(id: SkillID) async throws -> SkillManifest {
        if let store {
            let manifest = try await store.load(id: id)
            guard manifest.id == id else {
                throw SkillExecutionError.unknownSkill(id)
            }
            return manifest
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


    /// Returns the capabilities M6 must authorize for a Skill, including the
    /// concrete Module contract for exact built-in module-backed Skill bindings.
    public func requiredCapabilities(for id: SkillID) async throws -> CapabilityLevel {
        let manifest = try await manifestForVerification(id: id)
        guard manifest.id == id else { throw SkillExecutionError.unknownSkill(id) }

        let moduleBackedSkillIDs: Set<String> = [
            "workspace.search", "workspace.read-file", "workspace.create-file"
        ]
        guard moduleBackedSkillIDs.contains(id.rawValue) else {
            return manifest.requiredCapabilities.union(.execute)
        }
        guard let rawModuleID = manifest.metadata["moduleID"],
              !rawModuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillExecutionError.malformedSkill
        }
        let moduleID = ModuleID(rawValue: rawModuleID)
        guard BuiltInModuleSkillBinding.matches(manifest: manifest, moduleID: moduleID),
              let moduleRuntime,
              let contract = await moduleRuntime.contracts().first(where: { $0.id == moduleID }),
              contract.inputSchema.identifier == manifest.inputSchema.identifier,
              contract.outputSchema.identifier == manifest.outputSchema.identifier else {
            throw SkillExecutionError.malformedSkill
        }
        return manifest.requiredCapabilities.union(contract.capabilities).union(.execute)
    }

    /// Reports executor availability without executing a Skill or granting permissions.
    public func executorAvailability(for id: SkillID) async -> SkillExecutorAvailability {
        guard !disabled.contains(id.rawValue) else { return .unavailable }

        let manifest: SkillManifest
        do {
            manifest = try await manifestForVerification(id: id)
        } catch {
            return .unavailable
        }
        guard manifest.id == id else { return .unavailable }

        // Explicitly registered executors are host-authorized by exact Skill ID.
        if await executors.executor(for: id.rawValue) != nil {
            return .available
        }

        if id == Self.normalizationManifest.id || manifest.metadata["executor"] == "text.normalize" {
            return Self.hasNormalizationSchema(manifest) ? .available : .unavailable
        }

        guard let rawModuleID = manifest.metadata["moduleID"],
              !rawModuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let moduleRuntime else {
            return .unavailable
        }
        let moduleID = ModuleID(rawValue: rawModuleID)
        guard BuiltInModuleSkillBinding.matches(manifest: manifest, moduleID: moduleID),
              let contract = await moduleRuntime.contracts().first(where: { $0.id == moduleID }),
              contract.inputSchema.identifier == manifest.inputSchema.identifier,
              contract.outputSchema.identifier == manifest.outputSchema.identifier else {
            return .unavailable
        }
        return .available
    }

    public func verify(id: SkillID, outputJSON: String) async throws -> Bool {
        try Task.checkCancellation()
        guard !disabled.contains(id.rawValue) else { return false }
        let manifest = try await manifestForVerification(id: id)
        try Task.checkCancellation()
        guard let executor = await resolveExecutor(for: manifest) else { return false }
        try Task.checkCancellation()
        // Standalone verification must enforce the manifest's output contract too;
        // an executor's own verifier is not allowed to override schema violations.
        // Keep the legacy empty-schema form unconstrained for opaque text outputs.
        if manifest.outputSchema.rawJSON.trimmingCharacters(in: .whitespacesAndNewlines) != "{}" {
            do {
                try SkillJSONSchemaValidator.validate(inputJSON: outputJSON, schema: manifest.outputSchema)
            } catch {
                return false
            }
        }
        let verified = try await executor.verify(manifest: manifest, outputJSON: outputJSON)
        try Task.checkCancellation()
        return verified
    }

    private static func hasNormalizationSchema(_ manifest: SkillManifest) -> Bool {
        manifest.inputSchema.identifier == Self.normalizationManifest.inputSchema.identifier
            && manifest.outputSchema.identifier == Self.normalizationManifest.outputSchema.identifier
    }

    private func resolveExecutor(for manifest: SkillManifest) async -> (any SkillExecutor)? {
        if let registered = await executors.executor(for: manifest.id.rawValue) {
            return registered
        }
        // The canonical built-in ID remains supported directly.
        if manifest.id == Self.normalizationManifest.id {
            return TextNormalizeSkillExecutor()
        }
        // Skill.md may declare this one host-supported alias. Never instantiate
        // arbitrary executor names from manifest metadata, and require the exact
        // normalization schema contract before honoring the alias.
        if manifest.metadata["executor"] == "text.normalize",
           Self.hasNormalizationSchema(manifest) {
            return TextNormalizeSkillExecutor()
        }
        guard let rawModuleID = manifest.metadata["moduleID"],
              !rawModuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let moduleRuntime else {
            return nil
        }
        let moduleID = ModuleID(rawValue: rawModuleID)
        guard BuiltInModuleSkillBinding.matches(manifest: manifest, moduleID: moduleID) else {
            return nil
        }
        return ModuleBackedSkillExecutor(moduleRuntime: moduleRuntime, moduleID: moduleID)
    }
}

private enum BuiltInModuleSkillBinding {
    static func matches(manifest: SkillManifest, moduleID: ModuleID) -> Bool {
        let expected: (moduleID: String, adapter: String)
        switch manifest.id.rawValue {
        case "workspace.search":
            expected = ("tool.workspace.read", "workspace.search")
        case "workspace.read-file":
            expected = ("tool.workspace.read", "workspace.read-file")
        case "workspace.create-file":
            expected = ("tool.workspace.write", "workspace.create-file")
        default:
            return false
        }
        return moduleID.rawValue == expected.moduleID
            && manifest.metadata["moduleID"] == expected.moduleID
            && manifest.metadata["chatInputAdapter"] == expected.adapter
    }
}

private struct ModuleBackedSkillExecutor: SkillExecutor {
    let moduleRuntime: ModuleRuntime
    let moduleID: ModuleID

    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        guard BuiltInModuleSkillBinding.matches(manifest: manifest, moduleID: moduleID) else {
            throw SkillExecutionError.malformedSkill
        }
        let contract = try await matchingContract(for: manifest)
        guard let data = inputJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["text"],
              let rawText = object["text"] as? String,
              let adapter = manifest.metadata["chatInputAdapter"] else {
            throw SkillExecutionError.malformedSkill
        }
        let argumentsObject: [String: String]
        switch adapter {
        case "workspace.search":
            let query = Self.parseWorkspaceSearchQuery(rawText)
            guard !query.isEmpty, query.count <= 256 else {
                throw SkillExecutionError.malformedSkill
            }
            argumentsObject = ["operation": "search", "query": query]
        case "workspace.read-file":
            guard let path = Self.parseWorkspaceReadPath(rawText) else {
                throw SkillExecutionError.malformedSkill
            }
            argumentsObject = ["operation": "read", "path": path]
        case "workspace.create-file":
            guard let request = Self.parseCreateFileRequest(rawText) else {
                throw SkillExecutionError.malformedSkill
            }
            argumentsObject = [
                "operation": "write",
                "path": request.path,
                "content": request.content
            ]
        default:
            throw SkillExecutionError.malformedSkill
        }
        let arguments = try JSONSerialization.data(withJSONObject: argumentsObject, options: [.sortedKeys])
        let fields = ["arguments": String(decoding: arguments, as: UTF8.self)]
        let result = try await moduleRuntime.execute(
            ModuleInvocation(moduleID: moduleID, input: ModulePayload(schema: contract.inputSchema, fields: fields))
        )
        let encoded = try JSONSerialization.data(withJSONObject: result.output.fields, options: [.sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }

    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        guard BuiltInModuleSkillBinding.matches(manifest: manifest, moduleID: moduleID),
              (try? await matchingContract(for: manifest)) != nil,
              let data = outputJSON.data(using: .utf8),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let toolJSON = envelope["output"],
              let toolData = toolJSON.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: toolData)) as? [String: Any],
              let operation = payload["operation"] as? String else {
            return false
        }

        switch manifest.metadata["chatInputAdapter"] {
        case "workspace.read-file":
            guard operation == "read",
                  payload["verified"] as? Bool == true,
                  let path = payload["path"] as? String,
                  Self.isSafeRelativePath(path, roots: ["workspace"]),
                  let content = payload["content"] as? String,
                  let byteCount = payload["bytes"] as? Int,
                  byteCount == content.utf8.count,
                  byteCount <= 256 * 1024 else {
                return false
            }
            return true
        case "workspace.create-file":
            guard operation == "write",
                  payload["verified"] as? Bool == true,
                  let path = payload["path"] as? String,
                  Self.isSafeRelativePath(path, roots: ["agents", "skills", "modules", "tools", "workspace"]),
                  let byteCount = payload["bytes"] as? Int,
                  (0...256 * 1024).contains(byteCount) else {
                return false
            }
            return true
        case "workspace.search":
            guard operation == "search",
                  let query = payload["query"] as? String,
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.count <= 256,
                  let matches = payload["matches"] as? [String],
                  matches.count <= 50,
                  matches.allSatisfy({ Self.isSafeRelativePath($0, roots: ["agents", "skills", "modules", "tools", "workspace"]) }),
                  let visited = payload["visited"] as? Int,
                  (0...500).contains(visited),
                  payload["truncated"] as? Bool != nil else {
                return false
            }
            return true
        default:
            return false
        }
    }

    private static func isSafeRelativePath(_ path: String, roots: Set<String>) -> Bool {
        guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/"), !path.contains("\\") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              let root = components.first?.lowercased(),
              roots.contains(root) else {
            return false
        }
        return components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
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

    private static func parseWorkspaceSearchQuery(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = trimmed
        let politePrefixes = ["hãy ", "vui lòng ", "giúp tôi ", "giúp mình ", "làm ơn ", "anh ", "em "]
        while let prefix = politePrefixes.first(where: { command.lowercased().hasPrefix($0) }) {
            command = String(command.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = command.lowercased()
        let emptyCommands: Set<String> = [
            "tìm kiếm trong workspace", "tìm kiếm trong workspace:",
            "tìm trong workspace", "tìm trong workspace:",
            "tìm kiếm workspace", "tìm kiếm workspace:",
            "search workspace for", "search workspace for:",
            "search workspace", "search workspace:",
            "find in workspace", "find in workspace:",
            "find workspace", "find workspace:"
        ]
        if emptyCommands.contains(normalized) {
            return ""
        }
        let prefixes = [
            "tìm kiếm trong workspace: ", "tìm kiếm trong workspace ",
            "tìm trong workspace: ", "tìm trong workspace ",
            "tìm kiếm workspace: ", "tìm kiếm workspace ",
            "search workspace for: ", "search workspace for ",
            "search workspace: ", "search workspace ",
            "find in workspace: ", "find in workspace ",
            "find workspace: ", "find workspace "
        ]
        guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
            return command
        }
        return String(command.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseWorkspaceReadPath(_ rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = trimmed
        let politePrefixes = ["hãy ", "vui lòng ", "giúp tôi ", "giúp mình ", "làm ơn ", "anh ", "em "]
        while let prefix = politePrefixes.first(where: { command.lowercased().hasPrefix($0) }) {
            command = String(command.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = command.lowercased()
        let prefixes = [
            "đọc file ", "đọc tệp ", "đọc workspace/",
            "mở file ", "mở tệp ", "mở workspace/",
            "read file ", "read workspace/",
            "open file ", "open workspace/",
            "show file ", "show workspace/"
        ]
        let candidate: String
        if let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) {
            // These prefixes include the workspace root itself. Preserve that root
            // so the common path validator still receives a workspace-relative path.
            if prefix.hasSuffix("workspace/") {
                candidate = "workspace/" + String(command.dropFirst(prefix.count))
            } else {
                candidate = String(command.dropFirst(prefix.count))
            }
        } else {
            candidate = command
        }
        let path = candidate.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\\\"'"))
        )
        guard path.count <= 512, isWorkspaceReadPath(path) else { return nil }
        return path
    }

    private static func isWorkspaceReadPath(_ path: String) -> Bool {
        guard path.hasPrefix("workspace/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count >= 2
            && components[0] == "workspace"
            && components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func parseCreateFileRequest(_ rawText: String) -> (path: String, content: String)? {
        // Keep the payload suffix byte-for-byte after the explicit content delimiter.
        // Only leading whitespace belongs to command normalization.
        var normalized = String(rawText.drop(while: { $0.isWhitespace }))
        // Match the read/search adapters: strip only known polite lead-ins at the
        // command boundary, leaving the path/content grammar and safety checks intact.
        let politePrefixes = ["hãy ", "vui lòng ", "giúp tôi ", "giúp mình ", "làm ơn ", "anh ", "em ", "please ", "kindly "]
        while let prefix = politePrefixes.first(where: { normalized.lowercased().hasPrefix($0) }) {
            normalized = String(normalized.dropFirst(prefix.count))
                .drop(while: { $0.isWhitespace })
                .description
        }
        let prefixes = [
            "tạo một file ", "tạo một tệp ", "tạo file ", "tạo tệp ",
            "create a file ", "create file ", "write a file ", "write file ",
            "make a file ", "make file "
        ]
        guard let prefix = prefixes.first(where: { normalized.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let remainder = String(normalized.dropFirst(prefix.count))
        // Accept common Vietnamese/English chat phrasing and punctuation variants.
        // Choose the earliest boundary so delimiters in file content are preserved.
        let delimiters = [
            " với nội dung là:", " với nội dung:", " nội dung là:", " nội dung:",
            " with content:", " content:", " với nội dung là ", " với nội dung ",
            " nội dung là ", " nội dung ", " with content ", " content ",
            "\nnội dung:", "\ncontent:"
        ]
        let matches = delimiters.compactMap { candidate -> (Range<String.Index>, String)? in
            guard let range = remainder.range(of: candidate, options: [.caseInsensitive]) else { return nil }
            return (range, candidate)
        }
        guard let delimiter = matches.min(by: { $0.0.lowerBound < $1.0.lowerBound }) else {
            return nil
        }
        let rawPath = String(remainder[..<delimiter.0.lowerBound])
        let path = rawPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\\\"'")))
        // Empty files are valid. The explicit delimiter establishes the content boundary.
        let rawContent = String(remainder[delimiter.0.upperBound...])
        // The delimiter is explicit: remove at most one conventional separator
        // space, but preserve meaningful indentation and blank lines in file content.
        let content: String
        if rawContent.hasPrefix(" ") {
            content = String(rawContent.dropFirst())
        } else if rawContent.hasPrefix("\r\n") {
            content = String(rawContent.dropFirst(2))
        } else if rawContent.hasPrefix("\n") {
            content = String(rawContent.dropFirst())
        } else {
            content = rawContent
        }
        guard !path.isEmpty else { return nil }
        return (path, content)
    }
}
