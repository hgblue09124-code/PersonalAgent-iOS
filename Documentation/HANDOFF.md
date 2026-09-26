# Task Handoff

## CURRENT STATE — read first

- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage migration, not final-complete**
- Active PR: **#91**
- Branch: `rearch/cognition-policy-runtime`
- Current tested commit: `d89321d3798316ab0e6eb5f3899ea730fb923c2b`
- Latest workflow: **#712 / 36254250956 — RED**
- iOS arm64: PASS
- Repository integrity: PASS
- Swift package tests: FAIL — Dependency direction, 1 issue
- Full Gate: FAIL

> FAST STOP: The immediate task is known. Do not open a new migration group until PR #91 is green.

## ISSUE #85 CONTINUITY

PR #87 → #88 → #89 → #90 → #91 are one connected execution chain for Issue #85. A green individual PR is a verified migration checkpoint, not Issue #85 completion.

### Completed / verified at prior checkpoints
- Architecture contract and ownership freeze.
- Kernel agent migration.
- Foundation → Kernel physical migration.
- Provider ownership migration checkpoints.
- App boundary/provider import repairs.
- Runtime foundation and storage/cache migration work now present in the current chain.

### Remaining
- Finish PR #91 Cognition/Policy/Runtime dependency migration and get Full Gate green.
- Complete remaining canonical physical migrations: Events, Memory, Storage, Capabilities, final Provider reconciliation, Composition, App, Tests/legacy duplicate cleanup.
- Final canonical-tree + dependency-direction audit.
- Physical iPhone 12 Pro Max validation.
- Final Issue #85 acceptance and close.

## EXACT NEXT ACTION

1. Inspect the confirmed #712 Dependency direction failure on current HEAD.
2. Identify the exact offending import/dependency from repository evidence.
3. Make the smallest repair; do not redesign architecture.
4. Re-run/check the new Full Gate.
5. If green, update TODO/HANDOFF/WORK_LOG and open the next confirmed migration scope.
6. If red again, inspect the new failing log before any further edit.

## DO NOT REDO

- Do not recalculate Issue #85 as 1/8.
- Do not restart ownership discovery; Audit #14 already froze ownership.
- Do not redo Foundation migration unless current evidence shows regression.
- Do not redesign UI.
- Do not optimize llama.cpp.
- Do not infer CI state from chat history.

## COMMUNICATION MAP

- AGENTS.md = execution contract.
- BASELINE.md = current snapshot.
- TODO.md = executable queue.
- WORK_LOG.md = chronological evidence.
- HANDOFF.md = exact next action.
- AUDIT.md = confirmed architecture/ownership.
- MEMORY.md = durable lessons.