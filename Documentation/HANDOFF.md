# Task Handoff

<!-- TASK-CONTEXT: This is the short-lived bridge between architecture tasks. The next worker should read this file first, then inspect the referenced source. Keep it concise and actionable. -->

## Current Task

**RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**

## Current State

- Runtime ownership cleanup has been completed and verified.
- Kernel coordination was reduced to the actually consumed module seam.
- Kernel contract imports/dependencies were minimized.
- PR #88 is an intermediate cleanup point, not the complete canonical migration.
- Canonical physical-tree migration has not yet been completed.

## Next Exact Action

1. Audit the complete repository tree.
2. Map every current component to exactly one Issue #85 canonical destination.
3. Identify components that require semantic splitting rather than a blind rename.
4. Record unresolved ownership decisions here and in `AUDIT.md`.
5. Only after mapping is complete, execute migration groups.

<!-- DO NOT REDO: Do not restart provider feature work. Do not redesign UI. Do not optimize llama.cpp. Do not invent new architecture folders before proving a boundary. Do not move files before the mapping audit is complete. -->

## Handoff Rule

After each task, replace this section with: Completed; Confirmed findings; Deferred findings; Tests/gates; Exact next action; Do not redo.
