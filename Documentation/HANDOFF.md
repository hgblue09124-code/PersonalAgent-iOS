# Task Handoff

## CURRENT STATE
- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Architecture migration: **IN FLIGHT on `rearch/architecture-canonical-clean`**
- Composition is already merged to `main` via PR #97.
- Architecture production target is being removed; `MilestoneGate` remains production-owned by Composition.
- ArchitectureManifest is test-only.

## CONFIRMED COMPLETED
- Kernel Agent group → canonical `Kernel/{Contracts,Errors,Ports}`
- Foundation → Kernel
- Events → `Kernel/Events`
- Provider ownership migration
- Memory target-boundary repair/checkpoint
- Cognition / Agency / Policy → Runtime ownership through PR #91
- Capabilities group → `Sources/Capabilities/{Modules,Skills,Tools}`

## CONFIRMED REMAINING CANONICAL GAPS
- `Sources/Observability` → Kernel/Ports contract ownership
- `Sources/Security` → Kernel/Ports + Storage/Configuration split
- `Sources/Memory` → remaining Memory semantic split

## EXACT NEXT ACTION
1. Run full gate for the Architecture clean branch.
2. Repair only evidence-backed failures.
3. Squash-merge the single logical Architecture task after green CI.
4. Then inspect Observability as the next smallest confirmed gap.


## 2026-09-27 — PR #94 Apple CI repair checkpoint

- PR #94 Capabilities migration code path is **not the source of the Apple CI failure**.
- Confirmed: Xcode arm64 build **PASS**.
- Confirmed: unsigned IPA creation and archive verification **PASS**.
- Confirmed: artifact upload **PASS**.
- Failure was only the PR-time `gh release create` call returning HTTP 403 `Resource not accessible by integration`.
- Minimal repair: remove the PR-time release publication step; keep the verified IPA artifact.
- Exact next action: re-run PR #94 Apple Native Build and verify the repair commit. Do not start another migration group until this gate is green.
