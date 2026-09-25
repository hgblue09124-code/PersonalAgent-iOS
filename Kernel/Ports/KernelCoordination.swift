/// Minimal kernel-to-runtime execution seam.
public struct KernelCoordinationBoundary: Sendable {
    public var modules: (any ModuleExecuting)?
    public init(modules: (any ModuleExecuting)? = nil) { self.modules = modules }
    public var isWiredForModules: Bool { modules != nil }
}
