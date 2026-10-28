# Agent-Ready Repository Contract

## P0 priority override: finish Alpha Agent Skills first

Before selecting any work, inspect [Issue #347 — Alpha Agent Skill completion gate](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/347). While it remains open, it is the highest-priority product objective: resume the next concrete blocker there before unrelated features, refactors, or cleanup. Continue autonomously through implementation, focused regression tests, CI repair, and physical-device acceptance. Do not mark verified from code presence or CI alone. The full gate is recorded on Issue #347 and in root `AGENTS.md`; if only the device step remains and no device is available, keep the issue open with an explicit blocker.

---

This directory defines the minimum execution contract for agents working in PersonalAgent-iOS. It complements, and does not replace, GitHub Issues, `AGENTS.md`, module contracts, tests, and CI.

## Continuous agent growth loop
- Default behavior: run the five-step loop continuously — Observe → Orient → Plan → Execute → Verify & Learn — one bounded task and one logical commit at a time; test, inspect CI, repair failures, then return to Observe.
- Keep this entrypoint short. Load [the detailed loop and context-recovery rules](../Documentation/RECURSIVE_AGENT_GROWTH_LOOP.md) only when needed.
- Never treat checkpoints as truth over current repo/task/CI evidence; never mark unverified work complete. Issue #347 remains P0 until its full acceptance gate, including physical-device evidence, is satisfied.

## Source of truth
- **Product intent:** product/architecture documentation and approved issues.
- **Executable work item:** a JSON task based on `task.schema.json`.
- **Implementation truth:** source code and the actual dependency graph.
- **Completion truth:** task-specific tests, diff review, commit SHA, and CI/device evidence appropriate to the change.
- **README is not a backlog.** Do not infer that a feature works merely because it is described.

## Before coding
1. Read root `AGENTS.md` and `Documentation/LESSONS.md`.
2. Reproduce or inspect the reported defect and identify the owning module.
3. Create or select one approved task contract in `Tasks/active/`.
4. Ensure scope, forbidden changes, acceptance criteria, verification commands, dependencies, and recovery are explicit.
5. If ownership or scope is unclear, stop and ask the planner; do not invent architecture or broaden scope.

## Guard commands
```sh
python3 Scripts/agent_task_guard.py validate Tasks/active/<task>.json
python3 Scripts/agent_task_guard.py check-diff Tasks/active/<task>.json --base origin/main
```
Use the actual target branch as the base. Fetch it first if needed. Scope matching uses declared glob patterns; review the final diff even when the guard passes.

## State rules
- `ready`: contract approved and dependencies available.
- `blocked`: a named dependency, permission, environment, or decision prevents safe progress.
- `in_progress`: implementation has started.
- `verified`: all required acceptance criteria have evidence recorded in `evidence`. Never set this based only on a successful compile, generated file, or agent assertion.
- A CI failure blocks dependent integration/release work but does not prevent independent tasks from progressing.
- One logical task = one logical commit. Update the issue after each commit; record CI status separately when it arrives.

## Guard limitations
The validator checks contract structure and changed-file scope. It does not prove behavior, review code quality, authorize dangerous operations, or replace CI, security review, live-provider tests, GGUF/device tests, or physical iPhone acceptance.
