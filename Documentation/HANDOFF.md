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

## Confirmed Findings
- Issue #85 is the root architecture/completion checkpoint.
- PRs #86 onward are implementation steps supporting Issue #85; a green individual PR is not equivalent to Issue #85 completion.
- Current re-architecture work must be evaluated as one integrated canonical migration, with dependency order preserved.
- No behavior change is intended unless a migration requires a minimal compatibility repair.

## Deferred Findings
- The full canonical migration is not yet complete.
- Intermediate PRs in the migration chain remain open and must not be treated as proof that Issue #85 is done.
- Final physical iPhone 12 Pro Max validation and complete Issue #85 acceptance review remain pending until the migration is complete.

## Tests / Gates
- PR #90 migration-group CI: GREEN.
- Full Issue #85 acceptance: NOT YET CONFIRMED.

## Exact Next Action
1. Continue from Issue #85 as the root source of truth.
2. Determine the remaining migration groups and their dependency order from the actual repository state.
3. Complete each group with regression tests, full CI, and architecture audit.
4. Do not declare re-architecture complete from an individual green PR.
5. At the end, run the integrated full gate, documentation continuity check, and physical iPhone 12 Pro Max validation.
6. Confirm every Issue #85 acceptance criterion before final integration/merge decisions.

<!-- DO NOT REDO: Do not restart provider feature work, UI redesign, llama.cpp optimization, or ownership discovery. -->
