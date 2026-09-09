import Foundation
import PAFoundation

public enum DeterministicModuleIDs {
    public static let echo = ModuleID(rawValue: "mod.echo")
    public static let reject = ModuleID(rawValue: "mod.reject")
    public static let privileged = ModuleID(rawValue: "mod.privileged")
    public static let hang = ModuleID(rawValue: "mod.hang")
    public static let fail = ModuleID(rawValue: "mod.fail")
    public static let compose = ModuleID(rawValue: "skill.echo")
    public static let unloaded = ModuleID(rawValue: "mod.unloaded")
}

public struct EchoModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.echo,
            name: "Echo",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.echo.in"),
            outputSchema: SchemaDocument(identifier: "mod.echo.out"),
            requiredFields: ["text"]
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        try Task.checkCancellation()
        let text = input.value(for: "text") ?? ""
        return ModulePayload(schema: contract.outputSchema, fields: ["text": text])
    }
}

public struct ValidationRejectModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.reject,
            name: "Reject",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.reject.in"),
            outputSchema: SchemaDocument(identifier: "mod.reject.out"),
            requiredFields: ["must"]
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: contract.outputSchema, fields: input.fields)
    }
}

public struct PrivilegedModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.privileged,
            name: "Privileged",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.destructive],
            inputSchema: SchemaDocument(identifier: "mod.privileged.in"),
            outputSchema: SchemaDocument(identifier: "mod.privileged.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: contract.outputSchema, fields: ["ok": "true"])
    }
}

public struct HangModule: Module {
    public let contract: ModuleContract

    public init(id: ModuleID = DeterministicModuleIDs.hang) {
        self.contract = ModuleContract(
            id: id,
            name: "Hang",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.hang.in"),
            outputSchema: SchemaDocument(identifier: "mod.hang.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        try Task.checkCancellation()
        return ModulePayload(schema: contract.outputSchema, fields: ["ok": "late"])
    }
}

public struct UnloadedModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.unloaded,
            name: "Unloaded",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.unloaded.in"),
            outputSchema: SchemaDocument(identifier: "mod.unloaded.out"),
            lifecycle: .unloaded
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        throw ModuleRuntimeError.invalidState(.idle)
    }
}

public struct FailingModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.fail,
            name: "Fail",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.fail.in"),
            outputSchema: SchemaDocument(identifier: "mod.fail.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        throw ModuleRuntimeError.executionFailed("deterministic")
    }
}

/// Meso skill: invokes an already-registered atomic module through the runtime port.
public struct EchoSkillModule: Module {
    public let contract: ModuleContract
    private let runtime: ModuleRuntime
    private let childID: ModuleID

    public init(runtime: ModuleRuntime, childID: ModuleID = DeterministicModuleIDs.echo) {
        self.runtime = runtime
        self.childID = childID
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.compose,
            name: "Echo Skill",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .meso,
            capabilities: [.read, .execute],
            dependencies: [childID],
            inputSchema: SchemaDocument(identifier: "mod.echo.in"),
            outputSchema: SchemaDocument(identifier: "mod.echo.out"),
            requiredFields: ["text"]
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        do {
            let result = try await runtime.execute(
                ModuleInvocation(moduleID: childID, input: input)
            )
            return result.output
        } catch let error as ModuleRuntimeError {
            throw ModuleRuntimeError.compositionFailed(error.description)
        }
    }
}
