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

## 5. CI and recovery loop

For every change:

1. Run the most specific tests first.
2. Run the task-contract and scope checks when the repository task contract applies.
3. Run the relevant CI workflows.
4. On failure, read the actual failing step/log, fix the smallest root cause, and rerun.
5. After green, continue forward. Do not stop the roadmap merely because optional device evidence is unavailable.

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

## 8. Default operating instruction

**Build → test → CI green → record evidence → expand.**
If CI fails, fix the failing cause. If CI passes, move forward to the next natural capability. Preserve security and honest reporting, but do not let repeated acceptance rituals replace product development.
