import PAFoundation

/// Explicit, deterministic registry. Not a global and not reflection-based.
public actor ModuleCatalog: ModuleCataloging {
    private var modules: [ModuleID: any Module] = [:]

    public init() {}

    public init(modules initial: [any Module]) throws {
        for module in initial {
            if modules[module.contract.id] != nil {
                throw ModuleRuntimeError.duplicateRegistration(module.contract.id)
            }
            modules[module.contract.id] = module
        }
    }

    public func register(_ module: any Module) throws {
        let id = module.contract.id
        if modules[id] != nil {
            throw ModuleRuntimeError.duplicateRegistration(id)
        }
        modules[id] = module
    }

    public func resolve(_ id: ModuleID) -> (any Module)? {
        modules[id]
    }

    public func contracts() -> [ModuleContract] {
        modules.values.map(\.contract).sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
