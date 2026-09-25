# Personal Agent — Architecture

## Status

**Current baseline:** M8 architecture foundation at verified green commit `e3e7182523daf711ba23cbc9ec67bd450ef44e5d`.

The repository currently uses the M8 package graph. This document therefore separates **CURRENT** from **TARGET**; the target is not presented as implemented.

This iOS client is the long-lived Personal Agent / Agent OS client. It is not a chat wrapper. Kernel is not an LLM.

Companion repositories (`agent-os`, `agent-core`, `agent-core-next`, `living-data-ocean`) are external material and must not become runtime dependencies.

## CURRENT — verified source graph

The current SwiftPM graph is approximately:

```text
App
  ↓
Composition
  ↓
PAKernel
  ├── PACognition → PAProviders / PAMemory / PASkills
  ├── PAAgency → PACognition / PATools / PAPolicy
  ├── PAModules
  ├── PAMemory
  ├── PAProviders
  └── PAEvents / PAObservability / PAPolicy

Composition additionally wires Providers / Local / Memory / Modules / Skills / Tools / Storage / Security / Policy / Cognition / Agency.
```

This is the **current implementation**, not the target. In particular, current `PAKernel` contains the AgentRuntime boundary while depending on several domain modules, and `M8CompositionRoot` contains local-model lifecycle coordination and product wiring.

## TARGET — responsibility architecture

```text
App
  ↓
Composition
  ↓
Runtime ───────── Capabilities
  ↓                    ↓
Kernel contracts     Modules / Skills / Tools
  ↑
Ports
  ↑
Providers / Memory / Storage / Device adapters
```

The target separates stable contracts from runtime orchestration and infrastructure responsibilities. Migration must prove each boundary before moving code.

## Layer responsibilities

| Layer | Owns | Must not own |
|---|---|---|
| App | rendering, input, presentation | runtime orchestration, provider SDKs, persistence |
| Composition | construction and wiring | business logic |
| Runtime | execution, planning, observation, verification, lifecycle orchestration | persistence implementation, vendor details |
| Kernel | stable contracts, identity, state, lifecycle contracts, events, ports and invariants | UI, concrete providers, infrastructure implementation |
| Capabilities | Modules, Skills, Tools | provider internals |
| Providers | provider contracts and remote/local adapters | UI and unrelated policy |
| Memory | memory semantics, classification and retrieval | physical persistence mechanics |
| Storage | durable persistence, sync, model/skill/config/cache storage | reasoning semantics |
| Device | platform/device adapters and capability signals | agent policy |

## Responsibility gaps to migrate

These are audit candidates, not permission for speculative refactoring:

1. PAKernel concentration: identify which AgentRuntime responsibilities can move behind Runtime-owned contracts.
2. Composition concentration: audit whether `LocalModelRuntimeCoordinator` belongs in Composition or a local-provider/runtime boundary.
3. Provider boundary: verify routing, provider contract and vendor adapter separation.
4. Memory/Storage: verify semantic memory is not coupled to physical persistence.
5. ArchitectureManifest: verify declarations match the actual SwiftPM graph.

## Quality bar

A change is complete only when responsibility is singular, dependencies are explicit, vendor knowledge is isolated, contracts are testable, behavior is preserved unless intentionally changed, and relevant verification gates are green.

## Historical milestone documentation

Existing `Documentation/M4.md` through `M8.md` remain historical/contract evidence. This document is the architecture entry point and does not replace those milestone records.
