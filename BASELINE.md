# BASELINE — PersonalAgent-iOS

## NOW
- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage canonical migration, not complete**
- Active PR: **#91 — rearch: migrate Cognition and Policy into canonical Runtime**
- Branch: `rearch/cognition-policy-runtime`
- Current tested commit before documentation sync: `ecc520c0a1871e30cd64c380c3bd8c0a88ed865a`
- Latest verified workflow before documentation sync: **#749 / 36260826735 — VERIFIED GREEN**
- iOS arm64 / repository integrity / Swift package tests / Full Gate / PR Final: **PASS**

## CURRENT QUEUE
1. Re-verify the current documentation-synced HEAD with a fresh Full Gate.
2. Inspect the next remaining Storage/Capabilities migration group.
3. Final canonical-tree/dependency audit.
4. Physical iPhone 12 Pro Max validation.
5. Issue #85 final acceptance/close.

## MEMORY CHECKPOINT
- Memory target-boundary blocker is resolved.
- `PAStorageMemory` owns storage-memory persistence/conformance.
- Memory semantics are physically split under Working/Retrieval; persistence is under Storage/Memory.

## VERIFICATION RULE
Any commit after #749 requires a new completed Full Gate before it is called verified.
