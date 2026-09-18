# Personal Agent — Architecture

Status: M0 contracts frozen. M1 kernel runtime implemented. M2 provider runtime implemented. M3 module runtime implemented. M4 Memory OS implemented (`Documentation/M4.md`). M5 Local + Cloud Storage / Sync implemented (`Documentation/M5.md`). M6 Cognition / Agency integrated (`Documentation/M6.md`). M7 Durable Run Lifecycle, Checkpointing & Recovery implemented (`Documentation/M7.md`). M8 Product Architecture Foundation specification and boundaries established (`Documentation/M8.md`).
No live LLM call in default composition.

This iOS client is the long-lived Personal Agent / Agent OS *client*.
It is not a chat wrapper. Kernel is not an LLM.

Companion repositories (`agent-os`, `agent-core`, `agent-core-next`, `living-data-ocean`)
are external material. They must not appear as runtime dependencies.

## Axis

```
UI (SwiftUI App)
  ↓
App Session / App Lifecycle
  ↓
Composition (M8CompositionRoot)
  ↓
Agent Kernel (AgentRuntime / AgentSession)
  ↓
Cognition / Memory / Agency / Policy / M7 Run Boundary
  ↓
Module / Skill / Tool / Provider contracts / Local Model Engine
  ↓
Storage / Sync / Product Persistence Container
  ↓
Events / Observability / Security / Device Capabilities
  ↓
Foundation
```

## Layer responsibilities

| Layer | Owns | Must not own |
| --- | --- | --- |
| UI | rendering, input, safe-area layout | goals, plans, storage, provider calls |
| App Session | user input boundary, session events | AgentState ownership, direct state mutations |
| Composition | wiring contracts for a process, product persistence | business logic |
| Kernel | identity, state, goals, lifecycle, coordination, durable run bounds | SwiftUI, concrete LLM, concrete store |
| Cognition | perception → reflection pipeline contracts | execution side effects |
| Agency | goal → adapt loop contracts | bypassing policy |
| Policy | capability + approval gate | tool implementations |
| Skills / Tools / Modules / Providers / Local Models | contracts + reserved adapter packages | agent state |
| Storage / Memory | contracts for local-first + sync, run stores, domain persistence | cloud vendor lock-in |
| Events | trace / replay / run provenance contracts | UI |
| Device Capabilities | thermal, memory, network, app lifecycle signals | UIKit/SwiftUI imports in Kernel |
| Security | secret + network boundaries | agent state |

## Milestone freeze

M0 freezes boundaries and contracts.
M1 implements Kernel runtime (`Documentation/M1.md`).
M2 implements the provider contract and runtime (`Documentation/M2.md`).
M3 implements the module / skill / tool runtime (`Documentation/M3.md`).
M4 implements the local-first Memory OS runtime & persistence (`Documentation/M4.md`).
M5 defines the Local + Cloud Storage / Sync architectural specification (`Documentation/M5.md`).
M6 implements Cognition / Agency integration gate (`Documentation/M6.md`).
M7 implements Durable Run Lifecycle, Checkpointing, Interruption Recovery & Capability Bounding (`Documentation/M7.md`).
M8 establishes the Product Architecture Foundation (`Documentation/M8.md`).

Kernel may hold `any LLMProvider`. It does not import `PAProvidersGrok` / OpenAI / Local.
Default composition wires `DeterministicFakeProvider`. Live vendor calls are a separate verification gate.
Kernel may hold `any ModuleExecuting` and request execution. It does not contain concrete modules.
Kernel may hold `any MemoryExecuting` and request memory operations. It does not contain concrete memory stores.
