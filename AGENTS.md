# AGENTS.md — PersonalAgent-iOS Working Rules

<!-- TASK-CONTEXT: This file is the default workflow contract for AI workers operating on this repository. Read it before starting architecture, repair, migration, or audit work. -->

## Mission

Keep PersonalAgent-iOS structurally coherent, testable, and incrementally evolvable.

## Mandatory Workflow

`inspect -> confirm -> minimal change -> regression test -> full gate -> audit -> record -> handoff`

### 1. Inspect

- Read the relevant Issue/PR.
- Inspect actual repository files and dependency declarations.
- Identify current ownership before proposing a move.
- Read `Documentation/ARCHITECTURE.md`, `Documentation/AUDIT.md`, and `Documentation/HANDOFF.md`.

### 2. Confirm

Classify every finding:
- **CONFIRMED** — repository evidence proves it.
- **NOT CONFIRMED** — evidence does not establish it.
- **DEFERRED** — valid but intentionally postponed.

Never manufacture bugs from architectural preference.

### 3. Minimal Change

- Fix only the confirmed scope.
- Prefer moving code before rewriting it during migration.
- Do not perform unrelated cleanup.
- Do not introduce generic folders without a proven boundary.

### 4. Regression Test

Every behavior change gets regression coverage. Architecture-only moves still require build/test verification.

### 5. Full Gate

Run applicable build, unit tests, dependency/architecture checks, and platform validation. Never call a task complete from a partial test.

### 6. Audit

After implementation, inspect the resulting structure and dependency direction again.

### 7. Record

Update the relevant Markdown in the same task.

<!-- INVARIANT: Code without recorded architectural reasoning is incomplete when the change affects ownership, boundaries, dependencies, migration, or future worker behavior. -->

Record: what changed; why; evidence; confirmed/deferred findings; verification; known limitations; exact next step.

### 8. Handoff

Leave the repository in a state where the next worker can continue without reconstructing the previous task from chat history. Update `Documentation/HANDOFF.md`.

## Architecture Rules

- Kernel = contracts/events/errors/ports; no vendor implementation.
- Runtime = agent execution/orchestration.
- Capabilities = modules/skills/tools.
- Providers = provider/model adapters.
- Memory = agent memory/retrieval semantics.
- Storage = persistence/data boundary.
- Composition = construction and wiring.
- App = presentation; no direct vendor/runtime/storage wiring.
- Tests mirror production ownership.

<!-- INVARIANT: One concept -> one place. One boundary -> one folder. One execution path -> one Runtime. One wiring point -> Composition. -->

## Stop Conditions

Stop and report instead of guessing when ownership is ambiguous, two canonical destinations appear equally valid, migration would require uncovered behavior changes, a test failure indicates a separate defect, or requested architecture conflicts with documented invariants.

## Handoff Template

```markdown
## Task Result

### Completed
- ...

### Confirmed
- ...

### Deferred
- ...

### Verification
- ...

### Next Exact Action
1. ...

### Do Not Redo
- ...
```

<!-- FINAL-CHECK: Before declaring completion, verify that code, tests, documentation, and handoff all describe the same repository state. -->