# Task Handoff

<!-- TASK-CONTEXT: Current continuation bridge for AI workers. Read this together with AGENTS.md, WORK_LOG.md, ARCHITECTURE.md and AUDIT.md. -->

## CURRENT STATE — read first

- Root task: **RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**
- PR: **#91**
- Branch: `rearch/cognition-policy-runtime`
- Current HEAD before this documentation update: `a2f8861966a79a86471e070743e1a2abb54c1a9a`
- Last verified Full Gate: run #614 (`36233267763`) — **VERIFIED GREEN**
- Issue #85 remains incomplete.

> FAST STOP: If current state and task boundary are known, STOP. Continue only for next-action details.

## Agent Communication Map

| File | Role | Agent action |
|---|---|---|
| `AGENTS.md` | mandatory execution contract | Read before work |
| `Documentation/WORK_LOG.md` | chronological footprint/evidence | Read latest entry; append completed cycles |
| `Documentation/HANDOFF.md` | current state / next action | Refresh after each completed task |
| `Documentation/AUDIT.md` | confirmed architecture/ownership | Record structural decisions here, not in WORK_LOG |
| `Documentation/AGENT_LEARNING_WORKFLOW.md` | verified repair-learning rules | Update only when a repair rule is actually learned/verified |

**Do not create another agent-log Markdown file unless a distinct ownership boundary is proven.**

## Completed

- Ownership freeze completed in Audit #14.
- Migration group #1 completed: Kernel agent source moved to canonical Kernel subdomains.
- Migration group #2 completed at its own change scope.
- Path-sensitive architecture tests and import-boundary checks updated and verified.
- PR #90 was CI green for its migration group.
- Auto-repair has a fail-closed Verified Learning loop: only approved deterministic rules may execute automatically; unknown failures are recorded as candidates; repeated fingerprints stop.
- Repair knowledge is stored in `.github/repair-knowledge.json`; candidate promotion is not automatic.
- Provider ownership migration for PR #91 has reached a verified-green Full Gate at run #610.

## Confirmed

- Issue #85 remains the root architecture/completion checkpoint.
- A green migration PR does not prove Issue #85 is complete.
- PR #91 is open and mergeable, but its current migration group still needs the broader Issue #85 acceptance sequence.
- Provider/runtime dependency direction is now verified by the green gate.
- Current repository documentation should distinguish **last verified code HEAD** from any later documentation-only HEAD.

## Deferred

- Full canonical migration is not complete.
- Final physical iPhone 12 Pro Max validation remains pending.
- Final Issue #85 acceptance review remains pending.
- Candidate auto-repair rules still require explicit verification/promotion.

## Exact Next Action

1. On the next agent turn, re-fetch PR #91 and current HEAD.
2. Fetch workflow runs for the current HEAD.
3. If RED, inspect the failing job log and classify the root cause before changing code.
4. If GREEN, select the next confirmed migration scope from Issue #85/AUDIT.md.
5. Keep the footprint synchronized: code change → WORK_LOG entry → HANDOFF current state.

## Do Not Redo

- Do not restart provider feature work.
- Do not redesign UI.
- Do not optimize llama.cpp during architecture migration.
- Do not repeat ownership discovery already frozen in `Documentation/AUDIT.md`.
- Do not infer CI state from chat history.
- Do not create parallel log files that duplicate WORK_LOG/HANDOFF roles.
