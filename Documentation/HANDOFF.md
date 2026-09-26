# Task Handoff

## CURRENT STATE
- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage migration, not final-complete**
- PR #91: **MERGED** into `rearch/kernel-migration-2`
- Merge commit: `f31fcce9331c17435b4d31aaa5cdeb000b90bffb`
- Merge commit CI: **@github CI #753 — VERIFIED GREEN**
- Verified gates at merge commit: Swift package / repository integrity / iOS arm64 / Full Gate
- This document is the current handoff source; historical checkpoints remain in `AUDIT.md` and `WORK_LOG.md`.

## CONFIRMED COMPLETED
- Kernel Agent group → canonical `Kernel/{Contracts,Errors,Ports}`
- Foundation → Kernel
- Events → `Kernel/Events`
- Provider ownership migration
- Memory target-boundary repair/checkpoint
- Cognition / Agency / Policy → Runtime ownership through PR #91

## CONFIRMED REMAINING CANONICAL GAPS
From the verified `Package.swift` at merge commit:
- `Sources/Modules/Contracts` → `Capabilities/Modules`
- `Sources/Skills/Contracts` → `Capabilities/Skills`
- `Sources/Tools/Contracts` → `Capabilities/Tools`
- `Sources/Composition` → `Composition`
- `Sources/Architecture` → test-side ArchitectureManifest ownership; no production Architecture layer
- `Sources/Observability` → remaining contract/implementation split
- `Sources/Security` → remaining contract/configuration split
- `Sources/Memory` → remaining Memory semantic split
- Test topology still needs redistribution to mirror canonical ownership

These are **migration targets, not permission to move blindly**. Audit #14 remains the ownership authority.

## EXACT NEXT ACTION
1. Inspect the actual current tree and `Package.swift` for the next smallest **Capabilities** migration group.
2. Confirm file-level ownership and consumer imports.
3. Move before rewrite; change no behavior.
4. Run the full gate.
5. Update `AUDIT.md`, `WORK_LOG.md`, and this handoff with the exact verified checkpoint.

## MARKDOWN PROTOCOL
- `ARCHITECTURE.md` = long-lived normative architecture.
- `AUDIT.md` = evidence and classified findings only.
- `HANDOFF.md` = current state + one exact next action.
- `WORK_LOG.md` = chronological execution evidence.
- `AGENTS.md` = worker protocol and routing rules.
- Do not duplicate historical detail into `HANDOFF.md`.
- Do not use Markdown as proof of CI; cite the exact commit/workflow evidence in the record.

## DO NOT REDO
- Do not reopen resolved Memory/Foundation/Events/Cognition/Agency/Policy ownership without new evidence.
- Do not perform another architecture-discovery phase; ownership is frozen by Audit #14.
- Do not infer Issue #85 completion from a green intermediate PR.
- Do not modify production code as part of documentation-only work.
