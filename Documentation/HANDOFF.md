# Task Handoff

## CURRENT STATE
- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage migration, Capabilities group completed**
- Capabilities Migration: **COMPLETED & VERIFIED GREEN** (340/340 tests pass)
- This document is the current handoff source; historical checkpoints remain in `AUDIT.md` and `WORK_LOG.md`.

## CONFIRMED COMPLETED
- Kernel Agent group → canonical `Kernel/{Contracts,Errors,Ports}`
- Foundation → Kernel
- Events → `Kernel/Events`
- Provider ownership migration
- Memory target-boundary repair/checkpoint
- Cognition / Agency / Policy → Runtime ownership through PR #91
- Capabilities group → `Sources/Capabilities/{Modules,Skills,Tools}`

## CONFIRMED REMAINING CANONICAL GAPS
- `Sources/Composition` → `Composition`
- `Sources/Architecture` → test-side ArchitectureManifest ownership; no production Architecture layer
- `Sources/Observability` → remaining contract/implementation split
- `Sources/Security` → remaining contract/configuration split
- `Sources/Memory` → remaining Memory semantic split

## EXACT NEXT ACTION
1. Inspect the actual current tree and `Package.swift` for the next smallest migration group (e.g. Composition or Observability/Security).
2. Confirm file-level ownership and consumer imports.
3. Move before rewrite; change no behavior.
4. Run the full gate (`docker run --rm -v $(pwd):/src -w /src swift:6.3.2 swift test --disable-sandbox`).
5. Update `AUDIT.md`, `WORK_LOG.md`, and this handoff with the exact verified checkpoint.
