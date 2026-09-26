# Personal Agent — Architecture

Status: M0 contracts frozen. M1 kernel runtime implemented. M2 provider runtime implemented. M3 module runtime implemented. M4 Memory OS implemented (`Documentation/M4.md`). M5 Local + Cloud Storage / Sync implemented (`Documentation/M5.md`). M6 Cognition / Agency integrated (`Documentation/M6.md`). M7 Durable Run Lifecycle, Checkpointing & Recovery implemented (`Documentation/M7.md`). M8 Product Architecture Foundation specification and boundaries established (`Documentation/M8.md`).
No live LLM call in default composition.

This iOS client is the long-lived Personal Agent / Agent OS *client*.
It is not a chat wrapper. Kernel is not an LLM.

Companion repositories (`agent-os`, `agent-core`, `agent-core-next`, `living-data-ocean`)
are external material. They must not appear as runtime dependencies.

## Canonical dependency axis

```
UI (SwiftUI App)
  ↓
App Session / App Lifecycle
  ↓
Composition
  ↓
Runtime
  ↓
Kernel
  ↓
Capabilities / Providers / Memory / Storage
```

The physical repository layout is canonical. Production ownership follows the current tree rather than legacy target names.

| Domain | Owns |
| --- | --- |
| App | presentation and user/session boundary |
| Composition | dependency wiring and product composition |
| Runtime | execution, observation, planning, verification, result, provider lifecycle |
| Kernel | stable contracts, identity, state, goals, lifecycle, coordination, ports |
| Capabilities | executable Modules / Skills / Tools |
| Providers | remote and local provider adapters/runtime |
| Memory | working, conversation, long-term, retrieval semantics |
| Storage | persistence, model/configuration/cache infrastructure |
| Tests | architecture manifests, gates, regression and verification evidence |

## Operational Markdown + Cognitive Ocean

Personal Agent OS Markdown is the cognitive control/data plane around the executable architecture.

```
Operational Markdown
  AGENTS → ARCHITECTURE → AUDIT / HANDOFF / WORK_LOG / LESSONS
                         ↓
                   evidence / learning
                         ↓
              Living Cognitive Ocean
                   Modules/
                         ↓
                Agent reuse / action
                         ↓
                     Verify
                         ↓
                 new evidence
```

The two layers have separate responsibilities:

- **Operational Markdown** records how the Agent operates, what is verified, the current handoff, execution history, and durable lessons.
- **Living Cognitive Ocean** stores independently reusable evidence-backed grains.
- `Modules/` is persistent cognitive data and is distinct from executable `Sources/Capabilities/Modules`.
- Evidence can flow from operational audit/history into a confirmed grain, but neither layer becomes the other's diary or database.
- Grain lifecycle is `OBSERVED → CONFIRMED → PROMOTED`.
- Markdown remains canonical human-readable persistence.
- No parser, index, retrieval service, or rigid schema is introduced until real usage demonstrates a concrete retrieval gap.

## Markdown Cognitive Plane

Personal Agent OS Markdown is a product-level cognitive persistence plane above the runtime implementation.

```
Human Intent
    ↓
Markdown State
    ↓
Agent
    ↓
Action
    ↓
Evidence
    ↓
Markdown State
    ↓
Learn
    ↺
```

Markdown surfaces are assigned explicit roles:

- `AGENTS.md`: identity and operating rules.
- `Documentation/ARCHITECTURE.md`: world model and ownership.
- `Documentation/LESSONS.md`: durable evidence-backed learning.
- `Documentation/AUDIT.md`: verified claims and findings.
- `Documentation/HANDOFF.md`: current working state and next action.
- `Documentation/WORK_LOG.md`: execution history.

The Markdown plane does not replace Kernel, Runtime, Composition, or domain ownership. It records and routes cognitive state around them.

The canonical product loop is:

**Read → Act → Verify → Learn → Persist**

Future parser, index, retrieval, or semantic-memory implementations must preserve Markdown as the canonical human-readable persistence surface.

## Living Cognitive Data Ocean

The Markdown cognitive plane is organized as a Living Cognitive Data Ocean.

- **Sea of Chaos** contains observations, thoughts, raw events, and candidate material still requiring evaluation.
- **Living Ocean** contains evidence-backed cognitive grains ready for direct reuse.
- A grain is the smallest independently useful semantic unit; it is not defined by file size.
- Root `Modules/` is the persistent cognitive-data organization surface and is distinct from executable `Sources/Capabilities/Modules`.
- Grain lifecycle is **OBSERVED → CONFIRMED → PROMOTED**.
- A Module is a capability composition of relevant grains, not a folder.
- Future parser/index/retrieval/semantic-memory implementations must preserve Markdown as canonical human-readable persistence and must not silently promote unverified material.

```
Sea of Chaos
    ↓ evaluate
Living Grain
    ↓ select + compose
Cognitive Module
    ↓
Agent action
    ↓ verify
new evidence
    ↓
new / refined grain
```

The cognitive data plane is orthogonal to the executable dependency axis. It may inform runtime decisions only through existing ownership boundaries.

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
