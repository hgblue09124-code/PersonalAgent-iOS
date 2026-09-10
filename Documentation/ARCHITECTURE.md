# Personal Agent — Architecture

Status: M0 contracts frozen. M1 kernel runtime implemented. M2 provider runtime implemented. M3 module runtime implemented. M4 Memory OS implemented (`Documentation/M4.md`).
No live LLM call in default composition.

This iOS client is the long-lived Personal Agent / Agent OS *client*.
It is not a chat wrapper. Kernel is not an LLM.

Companion repositories (`agent-os`, `agent-core`, `agent-core-next`, `living-data-ocean`)
are external material. They must not appear as runtime dependencies.

## Axis

```
UI
  ↓
Composition
  ↓
Agent Kernel
  ↓
Cognition / Memory / Agency / Policy
  ↓
Module / Skill / Tool / Provider contracts
  ↓
Storage / Sync
  ↓
Events / Observability / Security
  ↓
Foundation
```

## Layer responsibilities

| Layer | Owns | Must not own |
| --- | --- | --- |
| UI | rendering, input, safe-area layout | goals, plans, storage, provider calls |
| Composition | wiring contracts for a process | business logic |
| Kernel | identity, state, goals, lifecycle, coordination | SwiftUI, concrete LLM, concrete store |
| Cognition | perception → reflection pipeline contracts | execution side effects |
| Agency | goal → adapt loop contracts | bypassing policy |
| Policy | capability + approval gate | tool implementations |
| Skills / Tools / Modules / Providers | contracts + reserved implementation packages | agent state |
| Storage / Memory | contracts for local-first + sync | cloud vendor lock-in |
| Events | trace / replay contracts | UI |
| Security | secret + network boundaries | agent state |

## Milestone freeze

M0 freezes boundaries and contracts.
M1 implements Kernel runtime (`Documentation/M1.md`).
M2 implements the provider contract and runtime (`Documentation/M2.md`).
M3 implements the module / skill / tool runtime (`Documentation/M3.md`).
M4 implements the local-first Memory OS runtime & persistence (`Documentation/M4.md`).
Later milestones fill cognition, events replay, then the iOS vertical slice.

M2 does not collapse Cognition into the Kernel.
Kernel may hold `any LLMProvider`. It does not import `PAProvidersGrok` / OpenAI / Local.
Default composition wires `DeterministicFakeProvider`. Live vendor calls are a separate verification gate.
Kernel may hold `any ModuleExecuting` and request execution. It does not contain concrete modules.
Kernel may hold `any MemoryExecuting` and request memory operations. It does not contain concrete memory stores.
