# Task Handoff

## CURRENT STATE
- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage migration, not final-complete**
- PR #91: **MERGED** into `rearch/kernel-migration-2`
- Merge commit: `f31fcce9331c17435b4d31aaa5cdeb000b90bffb`
- Merge commit CI: **@github CI #753 — VERIFIED GREEN**
- This document is the current handoff source; historical checkpoints remain in `AUDIT.md` and `WORK_LOG.md`.

## CONFIRMED COMPLETED
- Kernel Agent group → canonical `Kernel/{Contracts,Errors,Ports}`
- Foundation → Kernel
- Events → `Kernel/Events`
- Provider ownership migration
- Memory target-boundary repair/checkpoint
- Cognition / Agency / Policy → Runtime ownership through PR #91
- Markdown protocol optimization: `AGENTS.md` now carries project identity + compact routing; CI repair details moved to `Documentation/CI_REPAIR_PROTOCOL.md`.

## CONFIRMED REMAINING CANONICAL GAPS
From the verified `Package.swift` at the migration checkpoint:
- `Sources/Modules/Contracts` → `Capabilities/Modules`
- `Sources/Skills/Contracts` → `Capabilities/Skills`
- `Sources/Tools/Contracts` → `Capabilities/Tools`
- `Sources/Composition` → `Composition`
- `Sources/Architecture` → test-side ArchitectureManifest ownership; no production Architecture layer
- `Sources/Observability` → remaining contract/implementation split
- `Sources/Security` → remaining contract/configuration split
- `Sources/Memory` → remaining Memory semantic split
- Test topology still needs redistribution to mirror canonical ownership

These are migration targets, not permission to move blindly. Audit #14 remains the ownership authority.

## MARKDOWN PROTOCOL
- `AGENTS.md` = compact worker rules, project identity, routing, invariants.
- `ARCHITECTURE.md` = long-lived normative architecture.
- `AUDIT.md` = evidence and classified findings.
- `HANDOFF.md` = current state + one exact next action.
- `WORK_LOG.md` = chronological execution evidence.
- `CI_REPAIR_PROTOCOL.md` = specialized CI failure procedure.
- Markdown is not proof of code/CI; verify the referenced commit/workflow.

## EXACT NEXT ACTION
After the Modules migration CI gate is green, migrate `Sources/Skills/Contracts` → `Sources/Capabilities/Skills`; update only required path-sensitive references, run the full gate, then record the verified checkpoint in `AUDIT.md`, `WORK_LOG.md`, and this handoff.

## DO NOT REDO
- Do not reopen resolved Memory/Foundation/Events/Cognition/Agency/Policy ownership without new evidence.
- Do not perform another architecture-discovery phase; ownership is frozen by Audit #14.
- Do not infer Issue #85 completion from a green intermediate PR.
- Do not add more Markdown layers unless a concrete routing/knowledge gap is demonstrated.
