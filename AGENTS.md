# AGENTS.md — PersonalAgent-iOS Working Rules

<!-- TASK-CONTEXT: Default workflow contract for AI workers. Read before architecture, repair, migration, or audit work. -->

## Project Identity

PersonalAgent-iOS is a native iOS personal-agent system. Its canonical production architecture is:

`App → Composition → Runtime → Capabilities / Providers / Memory / Storage → Kernel`

- **Kernel** = contracts, events, errors, ports.
- **Runtime** = agent execution/orchestration.
- **Capabilities** = modules, skills, tools.
- **Providers** = model/provider adapters.
- **Memory** = agent memory/retrieval semantics.
- **Storage** = persistence/data boundary.
- **Composition** = construction and wiring.
- **App** = presentation.

<!-- INVARIANT: One concept -> one place. One boundary -> one folder. One execution path -> one Runtime. One wiring point -> Composition. -->

## Agent Memory Routing — FAST PATH

> Read order: `BASELINE.md` → relevant `Documentation/MEMORY.md` → only then `HANDOFF.md` / `AUDIT.md` / `WORK_LOG.md) when needed.

**STOP EARLY:** If the baseline/memory already answer the task, stop. Do not reconstruct repository state from the full Markdown tree or chat history.

Read Markdown from the top. Headings and routing hints are retrieval aids, not rigid parser rules. Useful data may grow below.

## Mandatory Workflow

`inspect → confirm → minimal change → regression test → full gate → audit → record → handoff`

### 1. Inspect
- Read the relevant Issue/PR.
- Inspect actual repository files and dependency declarations.
- Identify current ownership before proposing a move.
- Read `Documentation/ARCHITECTURE.md`, `Documentation/AUDIT.md`, and `Documentation/HANDOFF.md` when relevant.

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
Inspect the resulting structure and dependency direction again.

### 7. Record
Update relevant Markdown in the same task.

<!-- INVARIANT: Code without recorded architectural reasoning is incomplete when the change affects ownership, boundaries, dependencies, migration, or future worker behavior. -->

Record: what changed; why; evidence; confirmed/deferred findings; verification; known limitations; exact next step.

### 8. Handoff
Leave the repository in a state where the next worker can continue without reconstructing the previous task from chat history. Update `Documentation/HANDOFF.md`.

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

<!-- FINAL-CHECK: Before declaring completion, verify that code, tests, documentation, and handoff describe the same repository state. -->

## CI Failure / Repair Routing

When a workflow fails, follow `Documentation/CI_REPAIR_PROTOCOL.md` instead of expanding this file with CI-specific procedures.

Core rule:
- Verify PR/branch → current head SHA → workflow run → failed job/log.
- Confirm the root cause from evidence.
- Apply one minimal logical fix.
- Re-run and verify the full gate.
- If the workflow is incomplete, record **CHƯA XÁC MINH**.
- Unknown or repeated failures remain fail-closed; do not start a blind repair loop.

## Markdown Knowledge Protocol

<!-- TASK-CONTEXT: Keep worker memory compact and evidence-oriented. -->

- `Documentation/ARCHITECTURE.md` = normative long-lived architecture; not a chronological log.
- `Documentation/AUDIT.md` = evidence/classification only: CONFIRMED / NOT CONFIRMED / DEFERRED.
- `Documentation/HANDOFF.md` = current state + exactly one next action.
- `Documentation/WORK_LOG.md` = chronological execution evidence; include commit/workflow IDs when available.
- `Documentation/CI_REPAIR_PROTOCOL.md` = specialized CI failure investigation/repair procedure.
- Preserve useful `TASK-CONTEXT`, `DECISION`, `INVARIANT`, and `HANDOFF` comments.
- Never treat Markdown text as proof of code or CI state; verify the referenced commit/workflow first.
- After a migration checkpoint, update `AUDIT.md`, `WORK_LOG.md`, and `HANDOFF.md` in the same documentation task.
- Avoid duplicating old history in `HANDOFF.md`; keep durable historical evidence in `AUDIT.md` / `WORK_LOG.md`.
