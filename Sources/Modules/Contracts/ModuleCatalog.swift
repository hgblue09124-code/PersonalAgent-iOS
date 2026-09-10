import PAFoundation

/// Explicit, deterministic registry. Not a global and not reflection-based.
///
/// `dependencies` on a contract are catalog edges, not an execution graph.
/// Registration validates existence and rejects cycles. The catalog does not
/// invoke dependents.
public actor ModuleCatalog: ModuleCataloging {
    private var modules: [ModuleID: any Module] = [:]

    public init() {}

    public init(modules initial: [any Module]) throws {
        var seed: [ModuleID: any Module] = [:]
        for module in initial {
            if seed[module.contract.id] != nil {
                throw ModuleRuntimeError.duplicateRegistration(module.contract.id)
            }
            seed[module.contract.id] = module
        }
        try ModuleGraph.validate(seed)
        self.modules = seed
    }

    public func register(_ module: any Module) throws {
        let id = module.contract.id
        if modules[id] != nil {
            throw ModuleRuntimeError.duplicateRegistration(id)
        }
        var next = modules
        next[id] = module
        try ModuleGraph.validate(next)
        modules = next
    }

    public func resolve(_ id: ModuleID) -> (any Module)? {
        modules[id]
    }

    public func contracts() -> [ModuleContract] {
        modules.values.map(\.contract).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// Deterministic topological order of `id` and its declared dependencies.
    /// Dependencies appear before the module that lists them.
    public func dependencyOrder(of id: ModuleID) throws -> [ModuleID] {
        guard modules[id] != nil else {
            throw ModuleRuntimeError.unknownModule(id)
        }
        try ModuleGraph.validate(modules)
        return ModuleGraph.dependencyOrder(of: id, in: modules)
    }
}

enum ModuleGraph {
    static func validate(_ modules: [ModuleID: any Module]) throws {
        let ids = Set(modules.keys)
        for (id, module) in modules {
            for dep in module.contract.dependencies {
                if !ids.contains(dep) {
                    throw ModuleRuntimeError.missingDependency(module: id, missing: dep)
                }
            }
        }
        if let cycle = detectCycle(in: modules) {
            throw ModuleRuntimeError.dependencyCycle(cycle)
        }
    }

    static func dependencyOrder(of id: ModuleID, in modules: [ModuleID: any Module]) -> [ModuleID] {
        var seen: Set<ModuleID> = []
        var order: [ModuleID] = []
        func visit(_ current: ModuleID) {
            if seen.contains(current) { return }
            seen.insert(current)
            let deps = (modules[current]?.contract.dependencies ?? [])
                .sorted { $0.rawValue < $1.rawValue }
            for dep in deps {
                visit(dep)
            }
            order.append(current)
        }
        visit(id)
        return order
    }

    private static func detectCycle(in modules: [ModuleID: any Module]) -> [ModuleID]? {
        var visiting: Set<ModuleID> = []
        var visited: Set<ModuleID> = []
        var stack: [ModuleID] = []

        func dfs(_ id: ModuleID) -> [ModuleID]? {
            if visiting.contains(id) {
                let start = stack.firstIndex(of: id) ?? 0
                return Array(stack[start...]) + [id]
            }
            if visited.contains(id) { return nil }
            visiting.insert(id)
            stack.append(id)
            let deps = (modules[id]?.contract.dependencies ?? [])
                .sorted { $0.rawValue < $1.rawValue }
            for dep in deps {
                if let cycle = dfs(dep) { return cycle }
            }
            stack.removeLast()
            visiting.remove(id)
            visited.insert(id)
            return nil
        }

        for id in modules.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let cycle = dfs(id) { return cycle }
        }
        return nil
    }
}
