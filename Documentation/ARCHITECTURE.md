# PersonalAgent-iOS Architecture

<!-- TASK-CONTEXT: This is the long-lived architectural source of truth. Future workers MUST read this before changing structure, ownership, or dependency boundaries. Do not infer architecture from historical folder names alone. -->

## Purpose

PersonalAgent-iOS is organized around explicit boundaries:
- Kernel — stable contracts, events, errors, and ports.
- Runtime — agent execution and orchestration.
- Capabilities — executable skills, tools, and modules.
- Providers — model/provider adapters.
- Memory — agent data and retrieval semantics.
- Storage — persistence and data boundaries.
- Composition — dependency construction and wiring.
- App — presentation only.
- Tests — mirror production ownership.

## Canonical Structure

See Issue #85 (RE-ARCH — Canonical PersonalAgent-iOS structure) for the migration target.

<!-- INVARIANT: One concept -> one place. One boundary -> one folder. One execution path -> one Runtime. One wiring point -> Composition. Vendor-specific implementation stays behind an adapter boundary. -->

## Dependency Direction

`App -> Composition -> Runtime -> Capabilities / Providers / Memory / Storage -> Kernel`

<!-- INVARIANT: A lower layer must not depend upward on presentation or orchestration. Kernel must remain vendor- and UI-independent. -->

## Migration Rule

1. Audit before moving.
2. Map every current component to exactly one canonical home.
3. Move before rewriting.
4. Preserve behavior unless migration requires a minimal compatibility repair.
5. Verify after each move group.
6. Audit dependency direction after migration.
7. Record confirmed findings and deferred decisions.
8. Stop when one canonical form remains.

<!-- DECISION: Do not introduce generic containers such as Core, Manager, Service, Helper, Utils, or Misc unless a concrete boundary is proven and documented. -->

## Re-Architecture Completion Model

Issue #85 is the root Definition of Done for the canonical re-architecture. PRs/groups such as #86 onward are implementation steps toward that issue, not independent declarations that the re-architecture is complete.

A green PR means that its own change is verified. It does not by itself mean Issue #85 is complete.

Before declaring the re-architecture complete:
1. Finish the planned migration groups under Issue #85.
2. Verify the canonical structure and dependency direction as one integrated repository state.
3. Run the full required test/build gates and the required physical iPhone 12 Pro Max validation.
4. Confirm documentation continuity and the Issue #85 acceptance criteria.
5. Only then treat the re-architecture as complete and finalize/merge the resulting integration sequence according to its dependency order.

<!-- DECISION: Do not advance to another migration group merely because the previous PR is green. Use Issue #85 as the root completion checkpoint and keep intermediate PRs traceable to that root. -->

## Change Discipline

For every architecture task:
`inspect -> confirm -> minimal change -> regression test -> full gate -> audit -> record -> handoff`

<!-- HANDOFF: If a task discovers an issue but does not fix it, record CONFIRMED / NOT CONFIRMED / DEFERRED. Never leave future workers to infer status from prose. -->
