# Architecture Audit

<!-- TASK-CONTEXT: This file records evidence from architecture audits. It is not a wish list. Every finding must state whether it is confirmed, not confirmed, or deferred. -->

## Finding Format

- **Confirmed** — evidence exists in the repository.
- **Not Confirmed** — inspection did not establish the concern.
- **Deferred** — real concern exists but is intentionally postponed.

<!-- INVARIANT: Do not convert an architectural smell into a confirmed bug without evidence. Behavior bugs require a reproducible failure and regression coverage. -->

## Audit Log

### Audit #12 — Current recorded checkpoint

- Confirmed: unsupported `stateUpdate(.proposed)` must fail closed without mutation.
- Confirmed: runtime state/event atomicity fixes are covered by regression tests.
- Confirmed: Kernel contract imports and direct dependencies were minimized.
- Deferred: full canonical physical-tree migration from Issue #85.

<!-- HANDOFF: The next audit must start from the repository state on the active migration branch. Do not repeat already-verified behavioral fixes unless a migration touches them. -->

## Next Audit

### Canonical Tree Audit

Inspect the complete current tree and map every production/test component to the Issue #85 canonical structure.

Required output:
`Current path -> canonical path -> ownership evidence -> action -> confidence`

Do not move files during the mapping-only audit.
