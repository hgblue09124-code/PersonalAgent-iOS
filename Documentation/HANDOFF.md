# Task Handoff

<!-- TASK-CONTEXT: Issue #85 canonical migration bridge. Read AGENTS.md, ARCHITECTURE.md and AUDIT.md before continuing. -->

## Current Task
**RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**

## Completed
- Ownership freeze completed in Audit #14.
- Migration group #1 completed: Kernel agent source moved to canonical Kernel subdomains.
- Migration group #2 completed at its own change scope: Foundation/event/module execution contracts moved toward canonical Kernel contracts with compatibility bridges retained where required.
- Path-sensitive architecture tests and import-boundary checks updated and verified.
- PR #90 is CI green for the current migration group.
- Auto-repair now has a fail-closed Verified Learning loop: approved deterministic rules execute automatically; unknown failures are recorded as non-executable candidates; repeated fingerprints stop.
- Auto-repair regression is gated on an explicit `repaired=true` output, so an unknown classification cannot accidentally enter the regression/commit path.
- Repair knowledge is stored in `.github/repair-knowledge.json`; candidate promotion is intentionally not automatic.

## Confirmed Findings
- Issue #85 is the root architecture/completion checkpoint.
- PRs #86 onward are implementation steps supporting Issue #85; a green individual PR is not equivalent to Issue #85 completion.
- Current re-architecture work must be evaluated as one integrated canonical migration, with dependency order preserved.
- No behavior change is intended unless a migration requires a minimal compatibility repair.
- Automation may learn failure patterns as evidence, but only allowlisted deterministic repairs may execute automatically.

## Deferred Findings
- The full canonical migration is not yet complete.
- Intermediate PRs in the migration chain remain open and must not be treated as proof that Issue #85 is done.
- Final physical iPhone 12 Pro Max validation and complete Issue #85 acceptance review remain pending until the migration is complete.
- Candidate repair rules require explicit verification/promotion before they can become executable.

## Tests / Gates
- PR #90 migration-group CI: GREEN.
- Auto-repair workflow hardening committed on `3da9930f730215d06227175001b4e602d3de5b08`.
- Repair knowledge registry added on `9711036cab780baba18ed0aa60631c39a7c34571`.
- Full Issue #85 acceptance: NOT YET CONFIRMED.

## Current Provider Migration Checkpoint
- Migration Group #5 implementation has been applied to the PR #91 branch.
- CI for the new migration commit is **CHƯA XÁC MINH** until the new workflow run completes.
- Issue #85 remains open; physical iPhone validation and final acceptance are pending.

## Exact Next Action
1. Observe CI for the hardened auto-repair flow.
2. If RED, let only the approved deterministic rules repair and regress; unknown failures must stop and record a candidate.
3. Continue from Issue #85 as the root source of truth.
4. Determine the remaining migration groups and their dependency order from the actual repository state.
5. Complete each group with regression tests, full CI, and architecture audit.
6. Do not declare re-architecture complete from an individual green PR.
7. At the end, run the integrated full gate, documentation continuity check, and physical iPhone 12 Pro Max validation.
8. Confirm every Issue #85 acceptance criterion before final integration/merge decisions.

<!-- DO NOT REDO: Do not restart provider feature work, UI redesign, llama.cpp optimization, or ownership discovery. -->
