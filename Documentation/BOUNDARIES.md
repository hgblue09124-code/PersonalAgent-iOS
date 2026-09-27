# Layer Boundaries

## Target ownership

| Concern | Target owner |
|---|---|
| UI | App |
| Dependency construction | Composition |
| Agent execution | Runtime |
| Stable contracts, ports and invariants | Kernel |
| Modules / Skills / Tools | Capabilities |
| Remote / local provider adapters | Providers |
| Memory semantics | Memory |
| Durable persistence | Storage |
| Platform/device adapters | Device boundary |

## Current implementation caveat

The current M8 graph now separates `PARuntime` from `PAKernel`, with `AgentRuntime` owned by `PARuntime`. `PAKernel` still imports Cognition, Agency, Providers, Memory and Modules, so it is not yet a minimal contract-only core. `PAComposition` also owns significant local-model lifecycle and product wiring.

These are **architecture gaps to audit**, not confirmed bugs.

## Rules

- App must not import concrete provider implementations.
- Runtime must not persist directly in the target architecture.
- Memory must use storage contracts rather than storage internals.
- Provider contracts must not expose vendor-specific types.
- Vendor/native types stay inside their adapter boundary.
- Composition may know concrete implementations because it is the wiring boundary.
- Kernel must not depend on UI frameworks or concrete provider implementations.
- A new cross-layer dependency requires an explicit architectural decision.

Folders alone do not define architecture. SwiftPM targets, imports, contracts and ownership do.

## Migration

1. Identify current owner.
2. Identify intended owner.
3. Inspect imports, callers and tests.
4. Confirm the responsibility actually belongs elsewhere.
5. Move the smallest coherent unit.
6. Repair only confirmed breakage.
7. Run focused tests.
8. Run the full compatibility gate.
