# PersonalAgent-iOS Architecture

## Purpose

This is the architecture entry point. It separates the verified current baseline from the intended target so documentation never presents an unimplemented design as fact.

## Verified baseline

Recovery anchor: `e3e7182523daf711ba23cbc9ec67bd450ef44e5d`.

At this checkpoint both the M3 package workflow and Apple Native Build workflow were verified green. The baseline is preserved; migration proceeds in small independently verifiable slices.

## Target

```text
App
  ↓
Composition
  ↓
Runtime ───────── Capabilities
  ↓                    ↓
Kernel              Modules / Skills / Tools
  ↑
Ports / Contracts
  ↑
Providers / Memory / Storage / Device adapters
```

This is a dependency intent, not a claim about today's source tree.

## Ownership

| Layer | Owns | Must not own |
|---|---|---|
| App | SwiftUI presentation | Runtime, provider SDKs, persistence |
| Composition | construction and wiring | business logic |
| Runtime | execution, planning, observation, verification | persistence implementation |
| Kernel | stable contracts, ports, events, invariants | UI and concrete vendors |
| Capabilities | Modules, Skills, Tools | provider internals |
| Providers | provider contracts and adapters | UI and unrelated policy |
| Memory | memory semantics and retrieval | physical persistence |
| Storage | durable persistence and sync | reasoning semantics |
| Device | platform/device adapters | agent policy |

## Core rule

When current code differs from target, code is authoritative for current behavior and this document is authoritative for intended architecture. A migration task must state the gap before changing it.

## Quality bar

A change is architecturally complete only when responsibility is singular, dependencies are explicit, vendor knowledge is isolated, contracts are testable, behavior is preserved unless intentionally changed, and all relevant verification gates are green.
