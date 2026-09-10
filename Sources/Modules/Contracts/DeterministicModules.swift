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
    public static let wrongOutput = ModuleID(rawValue: "mod.wrong-output")
    public static let resistant = ModuleID(rawValue: "mod.resistant")
    public static let cycleA = ModuleID(rawValue: "mod.cycle.a")
    public static let cycleB = ModuleID(rawValue: "mod.cycle.b")
    public static let needsMissing = ModuleID(rawValue: "mod.needs-missing")
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

/// Cooperative hang. Honors task cancellation through `Task.sleep`.
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

/// Ignores task cancellation. Used to prove the runtime still returns
/// `.timeout` / `.cancelled` and never emits `.moduleCompleted`.
/// Swift cannot hard-preempt this body; the group waits for it to finish.
public struct CancellationResistantModule: Module {
    public let contract: ModuleContract
    public let spinNanoseconds: UInt64

    public init(spinNanoseconds: UInt64 = 80_000_000) {
        self.spinNanoseconds = spinNanoseconds
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.resistant,
            name: "Resistant",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.resistant.in"),
            outputSchema: SchemaDocument(identifier: "mod.resistant.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        let start = DispatchTime.now().uptimeNanoseconds
        var ticks = 0
        while DispatchTime.now().uptimeNanoseconds &- start < spinNanoseconds {
            ticks &+= 1
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return ModulePayload(
            schema: contract.outputSchema,
            fields: ["ok": "resistant", "ticks": String(ticks)]
        )
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

public struct WrongOutputModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.wrongOutput,
            name: "Wrong Output",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            inputSchema: SchemaDocument(identifier: "mod.wrong-output.in"),
            outputSchema: SchemaDocument(identifier: "mod.wrong-output.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: SchemaDocument(identifier: "not.the.output"), fields: ["x": "1"])
    }
}

public struct MissingDependencyModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.needsMissing,
            name: "Needs Missing",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            dependencies: [ModuleID(rawValue: "mod.does-not-exist")],
            inputSchema: SchemaDocument(identifier: "mod.needs-missing.in"),
            outputSchema: SchemaDocument(identifier: "mod.needs-missing.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: contract.outputSchema, fields: [:])
    }
}

public struct CycleAModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.cycleA,
            name: "Cycle A",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            dependencies: [DeterministicModuleIDs.cycleB],
            inputSchema: SchemaDocument(identifier: "mod.cycle.a.in"),
            outputSchema: SchemaDocument(identifier: "mod.cycle.a.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: contract.outputSchema, fields: [:])
    }
}

public struct CycleBModule: Module {
    public let contract: ModuleContract

    public init() {
        self.contract = ModuleContract(
            id: DeterministicModuleIDs.cycleB,
            name: "Cycle B",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: [.read, .execute],
            dependencies: [DeterministicModuleIDs.cycleA],
            inputSchema: SchemaDocument(identifier: "mod.cycle.b.in"),
            outputSchema: SchemaDocument(identifier: "mod.cycle.b.out")
        )
    }

    public func execute(_ input: ModulePayload) async throws -> ModulePayload {
        ModulePayload(schema: contract.outputSchema, fields: [:])
    }
}

/// Meso skill: invokes an already-registered atomic module through the runtime port.
/// This is the M3 skill execution path. It must not call the child module directly.
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
        try Task.checkCancellation()
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
