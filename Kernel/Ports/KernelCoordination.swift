import PAModules

/// Minimal kernel-to-runtime execution seam.
///
/// The kernel/runtime boundary exposes only the capability currently consumed
/// by AgentRuntime. Provider, memory, policy, cognition, and agency wiring
/// remains outside this contract.
public struct KernelCoordinationBoundary: Sendable {
    public var modules: (any ModuleExecuting)?
    public init(modules: (any ModuleExecuting)? = nil) { self.modules = modules }
    public var isWiredForModules: Bool { modules != nil }
}
