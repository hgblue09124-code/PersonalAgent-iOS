# Personal Agent iOS

Contract-driven Personal Agent / Agent OS client for iPhone.

This is not a chat-app wrapper. The LLM is a reasoning engine. The kernel owns identity, state, goals, lifecycle, and coordination.

**Milestone: M5 — Local + Cloud Storage / Sync Architecture.** M0–M4 remain in place.

Target device: iPhone 12 Pro Max · Swift 6 · SwiftUI · iOS 18+ · local-first · provider-agnostic.

## Status

| Layer | Status |
| --- | --- |
| Module boundaries + contracts | Present |
| Dependency direction tests | Present |
| SwiftUI shell (7 screens) | Present, no business logic |
| Kernel runtime | Present (lifecycle, goals, events) |
| Provider contract + runtime | Present |
| Concrete provider adapters | Present (fixture-tested; live network pending) |
| Module / skill / tool runtime | Present (deterministic modules; no privileged device tools) |
| Memory OS runtime & persistence | Present (FileBackedMemoryStore, MemoryIndex, MemoryRuntime) |
| Storage / sync engines | Local-first file engine present; M5 architecture defined |
| Device verification on iPhone 12 Pro Max | Not signed off |

Companion repositories (`agent-os`, `agent-core`, `agent-core-next`, `living-data-ocean`) are external material. They are not runtime dependencies.

## Layout

```
UI → Composition → Kernel
  → Cognition / Agency / Policy / Memory
  → Skills / Tools / Modules / Providers
  → Storage / Sync
  → Events / Observability / Security
  → Foundation
```

## Build

Package contracts (macOS or Linux with Swift 6):

```
swift test
```

iOS app: open `PersonalAgent.xcodeproj` in Xcode 16+, destination iPhone 12 Pro Max.

## Review notes

- Kernel must not import SwiftUI or a concrete provider module.
- Memory subsystem is contract-driven, local-first, actor-isolated, and uses multi-field indexing ($O(1)$ ID/Scope/Kind lookups).
- Tools must go through Policy.
- Provider credentials stay outside AgentState.
- Default app composition uses `DeterministicFakeProvider`. No production credentials. No launch-time network.
- No overwrite-without-conflict sync strategy.
- Production code must not use `print()`.
