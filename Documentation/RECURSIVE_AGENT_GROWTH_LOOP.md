# Recursive Agent Growth Loop

This document is the detailed operating specification for autonomous, evidence-driven work in PersonalAgent-iOS. The agent entrypoint should stay short: read `.agentos/README.md`, then consult this document only when it needs the full loop, context-recovery rules, or decision policy.

## Purpose

Keep an agent making useful progress across many bounded tasks without requiring the user to restate the plan, loading the entire repository into every context, or confusing intended behavior with verified behavior.

The loop is continuous, but every individual task is bounded by its contract, allowed paths, acceptance criteria, permissions, and recovery plan. Growth means extending proven end-to-end capability, not accumulating unrelated features.

## Five-step loop

### 1. OBSERVE — recover the actual state

At the beginning of a session and after every task:
- Check P0 Issue [#347](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/347) first; it overrides routine feature work while open and not externally blocked.
- Read `AGENTS.md`, `Documentation/LESSONS.md`, and this short entrypoint; load other documents only when relevant.
- Inspect the current branch/commit, active task contracts, open PRs, recent commits, failing checks, and the latest evidence for the selected task.
- Treat repository state, task contracts, issue acceptance, test output, and CI as truth. Chat history and old checkpoints are pointers, not authority.
- Distinguish code present, local tests passed, CI passed, merged, and physical-device verified.

Output: a compact state snapshot: goal, current commit, active task, last verified commit, evidence, blockers, next action.

### 2. ORIENT — choose the highest-value next slice

Select one task that advances the P0 gate or a verified dependency:
1. Fix the highest-priority reproducible blocker in Issue #347.
2. Add a focused regression test for the behavior or failure boundary.
3. Repair CI or integration failures on the relevant PR head.
4. If an external dependency blocks one item, mark it explicitly and continue independent, safe work.
5. Only after the P0 gate is satisfied, select the next approved product task.

Do not invent a new backlog from documentation. Reuse an existing issue/task when possible. Prefer the smallest slice that proves a user-visible behavior end-to-end. A Python planner may propose and coordinate tasks; Swift remains the authority for iOS UI, policy, approvals, execution, and verification.

Output: one selected task, its dependency rationale, and whether it is ready or blocked.

### 3. PLAN — define a small task contract

Before implementation, create or select exactly one `Tasks/active/*.json` contract conforming to `.agentos/task.schema.json`. It must state:
- goal and relevant context;
- allowed paths and forbidden changes;
- acceptance criteria that can be observed;
- exact verification commands/checks;
- dependencies and a recovery path.

Validate it with:

```sh
python3 Scripts/agent_task_guard.py validate Tasks/active/<task>.json
```

Keep one logical task to one logical commit. Do not create commits just for checkpoints, status notes, or handoffs. If a task needs paths outside its declared scope, stop and split/rescope through the task contract instead of silently broadening access.

Output: a validated, bounded task contract.

### 4. EXECUTE — implement, test, inspect

- Make the smallest useful change that satisfies the contract; do not weaken safety controls to make a test pass.
- Add/update focused regression tests, including fail-closed cases where relevant.
- Run the task's required local checks.
- Review the complete diff and validate scope:

```sh
python3 Scripts/agent_task_guard.py check-diff Tasks/active/<task>.json --base origin/main
```

Use the actual target branch as the base. On Linux, work only within the SPM package boundary; do not open or edit `PersonalAgent.xcodeproj` or `App/` without an Xcode-capable environment. Keep one logical commit per task.

Output: a focused commit plus test results and a clear list of anything not tested.

### 5. VERIFY & LEARN — record evidence, then loop

- Inspect CI for the exact commit/PR head; do not infer status from an older commit.
- On failure, inspect the real logs, fix the root cause within scope, rerun checks, and resume the queue.
- Record evidence on the relevant issue/PR and task contract. Set a task to `verified` only when all its required acceptance criteria have recorded evidence.
- For Issue #347, verify Agent Task Contract, M3, Apple Native Build & Unsigned IPA on the final PR head and perform physical-iPhone acceptance. If device access is unavailable, keep the gate open and record the explicit blocker.
- Add only reusable, evidence-backed lessons to `Documentation/LESSONS.md`; do not turn it into a session diary.
- Return to OBSERVE and select the next bounded task. Continue without routine user prompts while safe, useful work remains.

Output: verified evidence or an explicit blocker, a refreshed state snapshot, and the next task.

## Context budget and recovery

Keep three layers of context:

1. **Always loaded (small):** user/product goal, safety invariants, P0 priority, current task ID, current commit, last verified commit, and links to authoritative files/issues.
2. **Current task (bounded):** task contract, directly relevant source/tests, failing output, and acceptance evidence.
3. **On demand:** architecture details, old CI logs, unrelated PR history, prior task implementation details, and broad documentation.

Rules:
- Never load the whole repository or paste full CI logs by default. Retrieve only the relevant files, failing log section, and needed dependency context.
- Store links and concise findings rather than duplicating long logs.
- When context is running low, write a compact checkpoint in the existing task/issue/PR surface: `goal`, `current_state`, `current_commit`, `last_verified_commit`, `evidence`, `blockers`, `next_task`. Do not create a memory-only commit.
- After context reset, start at OBSERVE and reconstruct from the repo/issue/CI, not from the checkpoint alone.
- If checkpoint and fresh evidence disagree, trust the newest verifiable repository/CI/device state and correct the checkpoint.
- Persist durable lessons, not transient reasoning, speculative diagnoses, or a diary of every loop.

## Stop, block, or escalate

Continue autonomously for routine, reversible work inside the approved contract. Stop or mark only the affected task blocked when:
- required access, credentials, a physical device, or a human-only approval is unavailable;
- acceptance criteria conflict or the architecture/product decision is high-impact and irreversible;
- a change would require out-of-scope paths or broaden permissions;
- evidence is insufficient to safely choose a behavior.

A blocker is not permission to claim success. Record what is blocked, why, the evidence needed to unblock it, and continue independent safe work where possible.

## Completion and reporting

For each task, report only:
- changed behavior and commit;
- tests and CI evidence tied to that commit;
- device verification state, if relevant;
- remaining blocker and next task.

Batch routine progress reports; interrupt only for a material blocker, risk, or decision. Never claim that a PR is merged, CI is green, or a device test passed without direct evidence.

## Definition of a healthy loop

The loop is healthy when it repeatedly derives work from current evidence, makes bounded useful changes, validates them, survives a context reset, preserves the Alpha security boundary, and resumes without the user restating the plan. It must not be judged by the number of commits or by unchecked feature volume.
