import PAKernel
import PAModules

/// Resolves a Skill definition and delegates execution to the existing ModuleRuntime.
/// Skill invocation never bypasses Module contracts, capabilities, or validation.
public struct SkillInvoker: Sendable {
    private let catalog: SkillCatalog
    private let moduleRuntime: any ModuleExecuting

    public init(catalog: SkillCatalog, moduleRuntime: any ModuleExecuting) {
        self.catalog = catalog
        self.moduleRuntime = moduleRuntime
    }

    public func execute(
        skillID: String,
        input: ModulePayload,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> ModuleResult {
        guard let definition = catalog.resolve(id: skillID) else {
            throw ModuleRuntimeError.invalidInput("skillID")
        }

        return try await moduleRuntime.execute(
            ModuleInvocation(
                moduleID: definition.moduleID,
                input: input,
                timeoutNanoseconds: timeoutNanoseconds
            )
        )
    }
}
