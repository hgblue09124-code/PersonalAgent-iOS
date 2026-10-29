# PersonalAgent Vibe Coding Law

**Purpose:** Finish the application by expanding useful capabilities continuously, not by repeatedly circling the same completed area.

## 1. Primary rule: CI-green → expand naturally

1. Identify the next highest-value capability that naturally extends the current product.
2. Implement a small, coherent vertical slice rather than a speculative rewrite.
3. Run the CI workflows relevant to the changed code.
4. When the relevant CI is green, record the evidence and move to the next useful capability. Do not require the user to re-prove an already demonstrated behavior before unrelated work can continue.
5. If CI is red, diagnose the specific failing check and fix the cause; do not reopen unrelated, previously settled work.

A green CI run is sufficient to continue development. It is not a claim that an untested device-specific behavior has been verified.

## 2. Product direction

PersonalAgent should evolve toward a coherent personal-agent application with:

- A smooth, dependable chat experience and conversation search/actions.
- Agent orchestration, typed plans, Skill discovery, and clear progress/result states.
- A Python planning/orchestration core with versioned contracts, integrated incrementally with Swift.
- Swift-owned iOS permissions, policy decisions, tool execution, and result verification.
- Workspace/file operations, search, memory, and useful automations built on explicit capabilities.
- Clear settings for enabling/disabling features and transparent error recovery.
- Performance, accessibility, and maintainability improvements as part of feature work, not as an endless separate polish phase.

Prefer end-to-end user-visible capabilities. Avoid creating disconnected frameworks, duplicate runtimes, or documentation-only progress when a working feature can be built.

## 3. Definition of a useful increment

Each increment should include, as appropriate:

- A concrete user capability or a meaningful internal enabler for the next capability.
- A narrow task contract and explicit allowed paths.
- Tests that cover expected behavior and important failure paths.
- Relevant CI evidence.
- A short progress note stating what changed, which checks ran, and what comes next.

Do not add acceptance gates that are unrelated to the changed capability. Reuse historical evidence accurately; do not claim that old evidence proves a new build or a different behavior.

## 4. Security and authority boundaries

- Python may classify intent, plan, rank, and propose actions; it must not grant iOS permissions or bypass policy.
- Swift remains authoritative for permission prompts, Settings-backed capabilities, policy evaluation, tool execution, and verification of actual results.
- A plan or model response is not proof that an action executed.
- Fail closed when the requested capability is absent, the request is ambiguous, or required parameters are missing.
- Do not weaken tests, skip policy checks, expose secrets, or fabricate success to make CI green.

These boundaries enable faster product development; they are not a reason to block unrelated feature work.

## 5. CI and recovery loop — batch first, wait second

**Do not stop coding to wait for CI after each small edit or commit.** The default sequence is:

1. Define a coherent implementation batch from the current plan (related UI, logic, integration, and regression tests).
2. Implement the whole batch, including necessary adjacent fixes and tests, before treating CI as a checkpoint.
3. Run fast, targeted local checks during implementation when available; these must not become a reason to pause between routine edits.
4. Let CI run asynchronously while continuing independent work in the same planned batch or the next safe slice. Do not idle just because a workflow is queued or running.
5. Once the batch reaches a meaningful checkpoint, inspect the results for the exact relevant commit/head. If checks are still running, continue safe implementation or review rather than waiting passively.
6. If CI fails, inspect the actual failed step/log, fix the root cause in a focused follow-up batch, and rerun the affected checks. Avoid changing unrelated code just to chase a red status.
7. After the batch is implemented and its checks are resolved, record evidence and continue to the next planned batch.

Avoid needless commits or repeated CI-triggering commits for tiny, incomplete fragments. Group related changes into meaningful commits where practical. Do not postpone all testing until the very end of a large, unbounded project: use coherent batches and explicit checkpoints so failures remain diagnosable.

A CI-green result permits continued development and merge review under repository policy. It does not authorize claiming real-device, App Store, signing, background-execution, or performance behavior that the workflow did not test.

## 6. Prioritization

When choosing the next task, prefer in this order:

1. Complete a partially implemented, user-visible flow.
2. Connect an existing component that is currently disconnected.
3. Add a high-value capability that reuses existing architecture.
4. Improve reliability/performance where it directly improves a user flow.
5. Refactor only when it reduces complexity or enables the next capability.

Keep tasks small enough that failures are easy to localize. Avoid repeated PRs for the same behavior unless current evidence shows a regression.

## 7. Progress reporting

Every progress update should distinguish:
- **Implemented:** code present on the branch/commit.
- **CI:** named checks and their actual current result.
- **Integrated:** wired into the app, not merely a standalone package.
- **Device verified:** only when a relevant real-device run is documented.
- **Next:** the next useful increment.

Do not claim the application is finished until its intended product scope is implemented. Equally, do not use unfinished final acceptance of one feature as a blanket reason to stop expanding the rest of the app.

## 8. Continuous multi-commit execution mode

When the user asks to finish a plan, complete the app, or vibe code continuously, treat the plan as an execution queue, not as a deliverable to report and wait on.

1. **Plan once, execute continuously.** Convert the plan into ordered, independently verifiable slices. Start implementation immediately; do not stop after presenting the plan or ask the user to approve each routine slice.
2. **Vibe-code the batch before waiting for CI.** Finish the coherent implementation batch first: code, integration, adjacent fixes, and regression tests. Do not pause after each small edit/commit to watch CI. Workflows may run in the background; continue safe work while they run, then review their results at the batch checkpoint.
3. **Use multiple meaningful commits.** Prefer a sequence of focused commits that each deliver a coherent behavior, regression test, integration step, or root-cause fix. Do not collapse a multi-step feature into a documentation-only commit, and do not create artificial/no-op commits to inflate the count. Group related changes to avoid unnecessary CI churn.
4. **Keep moving after green CI.** When a batch's relevant checks pass, record the commit and evidence internally and begin the next queued batch in the same work session. Green CI is a continuation signal, not a stopping point.
5. **Recover in place.** When CI fails, inspect the exact failed job and logs, fix the root cause in a focused follow-up batch, rerun affected checks, then resume the queue. Do not abandon the rest of the plan because one slice failed.
6. **Maintain a live execution queue.** Reorder tasks only when evidence or a dependency requires it. Prioritize end-to-end user value and integration over isolated infrastructure, cosmetic refactors, or repeated planning.
7. **Batch the report at the end of a meaningful work session.** Report the plan's completed and remaining slices, commit/PR links, exact CI status, what is integrated versus standalone, blockers, and the next queue. Send an interim update only when the user needs to make a decision, a material blocker changes the plan, or a long-running task requires an accurate status update.
8. **Respect real limits without stopping unrelated work.** If a device, credential, review, or external action is unavailable, mark only the affected acceptance item as blocked and continue with other safe, independent slices. Never imply a blocked item passed.

A work session should aim to deliver several meaningful commits when scope allows, rather than one commit followed by a report. The objective is to finish the planned product work end-to-end, not merely to produce a plan, a branch, or a green workflow.

## 9. Default operating instruction

**Plan → vibe-code a coherent batch → run targeted tests → continue while CI runs → review CI at the checkpoint → fix failures → expand.**
Do not wait on CI after every small edit. Keep implementation moving while workflows run, but do not ignore failed checks or claim success without evidence. If CI fails, fix the failing cause. If CI passes, move forward to the next natural capability. Preserve security and honest reporting, but do not let repeated acceptance rituals replace product development.
