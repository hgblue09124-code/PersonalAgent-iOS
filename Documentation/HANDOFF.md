# Task Handoff

Last reconciled against GitHub: 2026-10-16.

## CURRENT STATE — SOURCE OF TRUTH

- Default branch: `main`. Read this file as an entry point, not as a substitute for checking current GitHub state.
- PR #452 merged as `62a9207f7603ce03edb32f7d9f22ee29e9e23b78`; it wires the Skill boundary into the canonical M8 Agent/chat orchestration path.
- PR #453 merged as `cdb9d4f44650a9c84512b3f308e8da5a331c5e47`; it adds an M8 composition regression for a Vietnamese workspace file-creation request, checking exact file contents and a successful, verified Skill observation.
- Task contract `Tasks/active/PASKILL-6.json` on main records PASKILL-6 as completed and states PR #454 passed required gates; reconcile that record against live Actions/check results instead of relying on stale PR body text.
- PR #454 merged as `d7b69c3371105d9ccbd399ae093d7fe08e45df2e`; it adds a negative regression proving workspace.create-file is not exposed and does not write or emit success when workspace tools are disabled. The PR description said CI was pending; inspect actual Actions/checks before treating this specific merge as verified.
- Issue #347 remains open. Skill execution is not complete: production executor mapping for installed Skills, unsupported/unauthorized fail-closed behavior, and broader policy/schema/approval/cancellation coverage remain to be proven.
- Issue #367 remains open for complete task-oriented UI flows and measured performance work.
- Issue #354 remains open as the end-to-end beta acceptance tracker. CI does not substitute for provider/GGUF runtime and physical iPhone acceptance.
- Issue #429 tracks the animated glass Agent Orb, startup “Attention Agent” error, and measured SwiftUI lag work. Preserve the approved orb direction and do not hide genuine runtime failures.

## NEXT ACTION — KEEP THIS ORDER

1. Reconcile the current `main`, open PRs, and latest Actions runs; record evidence, not assumptions.
2. Continue Issue #347 first: PASKILL-6 is recorded completed. Do not repeat its file-create tests. Inspect remaining production Skill/Module/Tool executor mappings and policy/schema/approval/cancellation boundaries, then choose the smallest uncovered gap and add regression evidence. Keep unsupported capabilities unavailable/fail-closed.
3. Validate the task contract with `python3 Scripts/agent_task_guard.py validate Tasks/active/<task>.json` and check the final diff against the actual PR target branch before committing.
4. Use one logical task = one logical commit. Update the relevant issue after the commit; report CI separately and only mark verified with recorded evidence.
5. Once the Skill path is evidenced, continue the highest-impact independent acceptance gaps under #354 and #367. Keep #429 scoped to its explicit UI files and verify the device separately.

## OPERATING CONTRACT

Before non-trivial work, read `AGENTS.md`, `Documentation/LESSONS.md`, `.agentos/README.md`, and `.agentos/task.schema.json`. Inspect the actual source and issue/PR state before editing. Do not trust old handoff claims over current GitHub evidence.

## PRODUCT INVARIANTS

- Markdown remains canonical human-readable persistence; do not add parser/index/database machinery without a demonstrated retrieval gap.
- Root `Modules/` is for human-readable cognitive grains; `Sources/Capabilities/Modules` is executable runtime code.
- Grain lifecycle: OBSERVED → CONFIRMED → PROMOTED.
- Skill execution must pass through the authorized runtime boundary; no prompt/LLM bypass, implicit broad grants, or model-claimed success.
- A result is successful only after real execution and the required independent verification.
- CI green is not proof of on-device acceptance. Record physical iPhone checks separately.
- One logical task = one logical commit. Keep changes minimal and continue independent work while CI runs.

## OPEN ACCEPTANCE TRACKERS

- [Issue #347 — Skill executors and verified execution](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/347)
- [Issue #367 — Complete UI workflows and performance](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/367)
- [Issue #354 — End-to-end beta acceptance](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/354)
- [Issue #429 — Orb, startup error, and UI lag](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues/429)
