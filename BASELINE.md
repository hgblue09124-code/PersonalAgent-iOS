# BASELINE — PersonalAgent-iOS

> FAST PATH: current repository truth. Historical details belong in MEMORY/WORK_LOG/AUDIT.

## NOW

- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage canonical migration, not complete**
- Active PR: **#91 — rearch: migrate Cognition and Policy into canonical Runtime**
- Branch: `rearch/cognition-policy-runtime`
- Current tested commit: `d89321d3798316ab0e6eb5f3899ea730fb923c2b`
- Latest workflow: **#712 / 36254250956 — RED**
- iOS arm64 build: **PASS**
- Repository integrity: **PASS**
- Swift package tests: **FAIL — Dependency direction, 1 issue**
- Full Gate: **FAIL**

## ISSUE #85 PROGRESS MODEL

Issue #85 is one continuous migration. PRs #87 → #91 are execution steps for the same Issue.

### Already completed from repository evidence
- Architecture contract / ownership model.
- Ownership freeze (Audit #14).
- Kernel agent migration.
- Foundation → Kernel physical migration.
- Multiple verified Provider/App/Runtime/storage migration and repair checkpoints.

### Current queue
1. Repair #712 Dependency direction failure.
2. Re-verify PR #91 Full Gate.
3. Audit remaining legacy ownership paths.
4. Complete remaining canonical migrations.
5. Final dependency/tree audit.
6. Physical iPhone 12 Pro Max validation.
7. Final Issue #85 acceptance and close.

## VERIFICATION RULE

The current HEAD is **not verified green**. Any later commit requires a new completed Full Gate.

## WORKER ROUTE

1. Read BASELINE.
2. Read TODO and MEMORY.
3. Inspect current PR/HEAD/CI.
4. Execute the first incomplete TODO item.
5. Verify.
6. Update WORK_LOG + HANDOFF + relevant memory.

## STOP EARLY

If the current section answers the task, stop reading deeper. Do not reconstruct state from old chat history.