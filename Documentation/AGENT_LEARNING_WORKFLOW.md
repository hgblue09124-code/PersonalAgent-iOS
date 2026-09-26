# Agent Learning Workflow — Verified Repair & Migration

> FAST READ: use current task/evidence first and stop once the required answer is established. This is a soft guide; useful memory may accumulate without strict schema parsing.

> Canonical operational form for AI workers in PersonalAgent-iOS.
> This document records **how the agent should work**, not new architecture.

## Core execution loop

`inspect -> confirm -> minimal change -> regression test -> full gate -> audit -> record -> handoff`

### 1. Inspect
- Read the relevant Issue/PR.
- Inspect the actual repository, files, targets, dependencies, tests, and current branch.
- Read `AGENTS.md`, `Documentation/ARCHITECTURE.md`, `Documentation/AUDIT.md`, and `Documentation/HANDOFF.md` when applicable.
- Do not infer repository state from chat history alone.

### 2. Confirm
Classify findings:
- **CONFIRMED** — repository evidence proves the failure/requirement.
- **NOT CONFIRMED** — evidence is insufficient.
- **DEFERRED** — valid but intentionally postponed.

No speculative bugs. No architecture changes from preference alone.

### 3. Minimal change
- Change only the confirmed scope.
- During migration: move before rewrite.
- Preserve behavior unless the task explicitly requires behavior change.
- Do not perform unrelated cleanup.
- Do not invent compatibility layers or substitute dependencies without evidence.

### 4. Regression
- Behavior change => add/update regression coverage.
- Architecture-only move => build/test verification is still mandatory.
- Re-run the failing check before declaring the repair valid.

### 5. Full gate
The completion gate is repository-wide, not only the latest PR:
- unit/build tests
- repository integrity / architecture checks
- dependency direction checks
- Apple build / unsigned IPA where applicable
- physical iPhone validation when required by the root acceptance gate

### 6. Audit
After the change:
- inspect the resulting tree
- inspect dependency direction
- verify no duplicate/ambiguous ownership was introduced
- verify code and tests match the canonical structure

### 7. Record
Record:
- what changed
- why
- evidence
- CONFIRMED / NOT CONFIRMED / DEFERRED findings
- verification
- known limitations
- exact next action

### 8. Handoff
Update `Documentation/HANDOFF.md` so the next agent can continue without reconstructing the task from chat.

---

## CI RED auto-repair policy

When CI fails:

```
CI RED
  ↓
classify failure
  ├─ known + deterministic + allowlisted → AUTO REPAIR
  │       ↓
  │    regression
  │       ↓
  │      CI
  │       ↓
  │    verify
  │       ↓
  │     audit
  │
  ├─ known but risky → STOP
  │
  ├─ unknown → record candidate + STOP
  │
  └─ repeated failure/fingerprint → STOP
```

### AUTO is allowed only when all are true
1. Failure pattern is explicitly allowlisted.
2. Repair is deterministic.
3. Scope is narrow and mechanically verifiable.
4. No architecture decision is being made.
5. Regression/full gate can verify the repair.

Otherwise stop.

### Unknown failure learning

```
unknown CI failure
      ↓
capture exact evidence/fingerprint
      ↓
record candidate rule
      ↓
human/verified repair
      ↓
regression proves repair
      ↓
extract deterministic pattern
      ↓
allowlist rule
      ↓
future occurrence may AUTO REPAIR
```

**Learning is verified promotion, not unrestricted self-modification.**

A new rule must not:
- invent architecture
- rewrite broad areas
- silently substitute dependencies
- bypass tests
- retry indefinitely
- convert an ambiguous failure into an automatic repair

### Current verified example

**R5 — stale SwiftPM dependency after target removal**
- Signal: SwiftPM reports an unknown `PA*` dependency and the target is absent from `Package.swift`.
- Repair: remove only the exact stale dependency entries.
- Risk: low.
- Regression: required.
- No dependency substitution.

This rule was promoted only after the failure was observed and the minimal repair was verified.

---

## Non-negotiable stop conditions

Stop and report when:
- ownership is ambiguous
- two canonical destinations are equally plausible
- behavior change is uncovered
- the failure is outside the allowlist
- the same fingerprint repeats
- the proposed fix requires architectural judgment
- the evidence conflicts with documented architecture

**Human owns architecture decisions. Agent owns execution within the verified boundary.**

## Final invariant

`One concept -> one place.`
`One boundary -> one folder.`
`One execution path -> one Runtime.`
`One wiring point -> Composition.`

Before completion, code, tests, documentation, and handoff must describe the same repository state.
