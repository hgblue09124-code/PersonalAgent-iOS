# CI Repair Protocol

<!-- TASK-CONTEXT: Specialized procedure for workflow failures. AGENTS.md routes here to keep the default agent context compact. -->

## Purpose

Repair CI from repository evidence, not from guesses.

## Required sequence

`PR/branch → head SHA → workflow run → failed job → job logs → confirmed root cause → minimal fix → new run → full-gate verification`

### 1. Identify the active work

- Verify the PR/branch first.
- Resolve the current head SHA.
- If a supplied SHA is not directly searchable, search the repository's open PRs before asking for a link.
- Use the newest relevant workstream only after confirming its head.

### 2. Inspect the failure

- Find the newest workflow run for the current head.
- Inspect the failed job and its logs.
- Classify the cause as **CONFIRMED**, **NOT CONFIRMED**, or **DEFERRED**.
- Do not infer a root cause from the workflow name alone.

### 3. Repair minimally

- Fix only the confirmed cause.
- Prefer one commit per logical fix.
- Do not combine unrelated cleanup or architecture changes.
- If the failure reveals a separate defect, stop and record it rather than expanding scope.

### 4. Verify

- Check the new workflow run.
- Verify the applicable full gate.
- If any required run is still pending, record **CHƯA XÁC MINH**.
- Repeated failures require a fresh log inspection; never perform blind retries or speculative repair loops.

## Completion record

Record:
- PR/branch
- head SHA
- workflow/run ID
- failed job
- confirmed root cause
- fix commit
- verification result
- remaining limitation
- next exact action

<!-- INVARIANT: A green workflow proves only the checks that actually ran; do not claim broader verification without evidence. -->
