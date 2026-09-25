# Layer Boundaries

| Concern | Owner |
|---|---|
| UI | App |
| Dependency graph | Composition |
| Agent execution | Runtime |
| Stable contracts and ports | Kernel |
| Modules / Skills / Tools | Capabilities |
| Remote / local provider adapters | Providers |
| Memory semantics | Memory |
| Persistence | Storage |
| Device/platform adapters | Device boundary |

## Rules

- App must not import concrete provider implementations.
- Runtime must not persist directly.
- Memory must use storage contracts rather than storage internals.
- Provider contracts must not expose vendor-specific types.
- Vendor/native types stay inside their adapter boundary.
- Composition may know concrete implementations because it is the wiring boundary.
- Kernel must not depend on UI frameworks or concrete providers.
- A new cross-layer dependency requires an explicit architectural decision.

Folders alone do not define architecture. SwiftPM targets, imports, contracts and ownership do.

## Migration

1. Identify current owner.
2. Identify intended owner.
3. Inspect imports and callers.
4. Move the smallest coherent unit.
5. Repair only confirmed breakage.
6. Run focused tests.
7. Run the full compatibility gate.
