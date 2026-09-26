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
- `Sources/Composition` → `Composition` **IN FLIGHT**
- `Sources/Architecture` → test-side ArchitectureManifest ownership; no production Architecture layer
- `Sources/Observability` → remaining contract/implementation split
- `Sources/Security` → remaining contract/configuration split
- `Sources/Memory` → remaining Memory semantic split

## EXACT NEXT ACTION
1. Verify the clean Composition branch with full CI.
2. Squash-merge the single logical Composition task into main only after CI is green.
3. Close contaminated PR #96; do not merge it.
4. After merge, inspect the next smallest confirmed canonical gap from current-tree evidence.


## 2026-09-27 — PR #94 Apple CI repair checkpoint

- PR #94 Capabilities migration code path is **not the source of the Apple CI failure**.
- Confirmed: Xcode arm64 build **PASS**.
- Confirmed: unsigned IPA creation and archive verification **PASS**.
- Confirmed: artifact upload **PASS**.
- Failure was only the PR-time `gh release create` call returning HTTP 403 `Resource not accessible by integration`.
- Minimal repair: remove the PR-time release publication step; keep the verified IPA artifact.
- Exact next action: re-run PR #94 Apple Native Build and verify the repair commit. Do not start another migration group until this gate is green.
