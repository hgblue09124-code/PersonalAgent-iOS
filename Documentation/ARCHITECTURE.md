# Personal Agent — Architecture

Status: M0 contracts frozen. M1 kernel runtime implemented. M2 provider runtime implemented. M3 module runtime implemented. M4 Memory OS implemented (`Documentation/M4.md`). M5 Local + Cloud Storage / Sync architectural specification defined (`Documentation/M5.md`). M6 Cognition / Agency integrated (`Documentation/M6.md`). M7 Durable Run Lifecycle & Interruption Recovery architectural specification defined (`Documentation/M7.md`; runtime pending).
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
Cognition / Memory / Agency / Policy / M7 Run Boundary
  ↓
Module / Skill / Tool / Provider contracts
  ↓
Storage / Sync / Run Persistence
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
| Kernel | identity, state, goals, lifecycle, coordination, durable run bounds | SwiftUI, concrete LLM, concrete store |
| Cognition | perception → reflection pipeline contracts | execution side effects |
| Agency | goal → adapt loop contracts | bypassing policy |
| Policy | capability + approval gate | tool implementations |
| Skills / Tools / Modules / Providers | contracts + reserved implementation packages | agent state |
| Storage / Memory | contracts for local-first + sync, run stores, checkpoints | cloud vendor lock-in |
| Events | trace / replay / run provenance contracts | UI |
| Security | secret + network boundaries | agent state |

## Milestone freeze

M0 freezes boundaries and contracts.
M1 implements Kernel runtime (`Documentation/M1.md`).
M2 implements the provider contract and runtime (`Documentation/M2.md`).
M3 implements the module / skill / tool runtime (`Documentation/M3.md`).
M4 implements the local-first Memory OS runtime & persistence (`Documentation/M4.md`).
M5 defines the Local + Cloud Storage / Sync architectural specification (`Documentation/M5.md`).
M6 implements Cognition / Agency integration gate (`Documentation/M6.md`).
M7 defines the Durable Run Lifecycle, Checkpointing, Interruption Recovery & Capability Bounding architectural specification (`Documentation/M7.md`; M7.0 architecture specification frozen, runtime implementation pending in M7.1+).
Later milestones fill events replay and the iOS vertical slice.

M2 does not collapse Cognition into the Kernel.
Kernel may hold `any LLMProvider`. It does not import `PAProvidersGrok` / OpenAI / Local.
Default composition wires `DeterministicFakeProvider`. Live vendor calls are a separate verification gate.
Kernel may hold `any ModuleExecuting` and request execution. It does not contain concrete modules.
Kernel may hold `any MemoryExecuting` and request memory operations. It does not contain concrete memory stores.
