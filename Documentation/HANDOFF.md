# Task Handoff

## CURRENT STATE — read first

- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- Issue #85: **OPEN — late-stage migration, not final-complete**
- Active PR: **#91**
- Branch: `rearch/cognition-policy-runtime`
- Current tested commit: `9b2f3b94ab57ddae7e46ef4cb2564cf2b485c17b`
- Latest verified workflow: **#718 / 36255114608 — VERIFIED GREEN**
- iOS arm64: PASS
- Repository integrity: PASS
- Swift package tests: PASS
- Full Gate: PASS
- PR Final — Filter: PASS

> FAST STOP: The previous #712 blocker is resolved. The next action is the confirmed physical-tree audit/migration queue.

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

1. Treat workflow #718 as the current verified baseline.
2. Audit actual remaining legacy physical groups from the current tree.
3. Start only the next confirmed migration group; no speculative redesign.
4. Run Swift tests, repository integrity, iOS arm64, and Full Gate.
5. Update TODO/WORK_LOG/MEMORY/HANDOFF with the new evidence.

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