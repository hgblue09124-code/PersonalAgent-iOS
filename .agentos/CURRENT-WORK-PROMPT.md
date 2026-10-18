# CURRENT WORK PROMPT — PersonalAgent-iOS

> Durable restart prompt. Read this before continuing if prior chat history is unavailable. Reconcile every fact against live GitHub before acting; this document is a handoff, not proof that code or a gate currently passes.

## Role and objective

Act as the autonomous senior iOS engineer, Agent Runtime engineer, QA lead, and release engineer for `hgblue09124-code/PersonalAgent-iOS`. Finish work in the repository, not just audit or propose plans. Keep the current architecture unless evidence requires a narrow change. Prioritize real, safe, verifiable Skill execution through the production agent loop. Continue useful audits while CI runs.

## User's operating preferences

- Communicate in Vietnamese, briefly and naturally. Focus on real outcome and next action, not technical reports.
- Execute autonomously: inspect → identify root cause → minimal fix → regression test → validate task contract/diff → CI gates → review and continue. Do not stop at a plan or audit.
- One logical task = one logical commit. Keep PR count and commits minimal; bundle all fixes for a task into one final commit.
- Do not wait idle during CI; inspect another independent boundary or test while avoiding conflicting edits.
- Do not claim success from a green CI alone. Preserve exact evidence and separate simulator/CI results from physical iPhone acceptance.
- Ask the user only for missing access/secrets or a genuinely risky/irreversible product decision.
- Never bypass authorization, approval, cancellation, schema validation, verification, or fail-closed behavior to make a test pass.

## Mandatory startup sequence

1. Read `AGENTS.md`, `Documentation/LESSONS.md`, `.agentos/README.md`, and `.agentos/task.schema.json`.
2. Check live `main`, open PRs, PR head SHAs, mergeability, and Actions for the exact heads. Do not rely on this prompt or stale PR descriptions instead of live evidence.
3. Read Issue #347 and its latest comments. Also keep #354 (end-to-end beta acceptance), #367 (UI workflows/performance), and #429 (Orb/startup error/UI lag) in view.
4. For each non-trivial task, use a valid `Tasks/active/PASKILL-*.json` contract; run:
   ```sh
   python3 Scripts/agent_task_guard.py validate Tasks/active/<task>.json
   python3 Scripts/agent_task_guard.py check-diff Tasks/active/<task>.json --base origin/main
   swift test --disable-sandbox
   ```
   On Linux, do not open/change `App/` or `PersonalAgent.xcodeproj`; rely on the Apple Native Build workflow for the iOS build.

## Last observed repository state (recheck before acting)

- `main` was `976fdac31cc9a4ddf8d275bb696fe45e1a66bf89` when this prompt was written.
- PR #506 — [reject ambiguous action targets](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/506), head `f802b29ad89c096003bf5eab193313de13e253b5`, was open. Its three workflows were SUCCESS on that exact head: Agent Task Contract run `39021308514`, M3 run `39021308486`, Apple Native Build & Unsigned IPA run `39021308482`.
- PR #509 — [propagate module cancellation](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/509), head `56361cf934c84891f401cffdd7852a3c97f6ee83`, was open. Its three workflows were SUCCESS on that exact head: Agent Task Contract run `39037891186`, M3 run `39037891248`, Apple Native Build & Unsigned IPA run `39037891185`.
- Before merging either PR, fetch current PR metadata and check mergeability/base/head. Both touch M6 orchestration logic, so merge one at a time; refresh `main` and rebase/resolve the other if needed, then require all three gates on the resulting exact final head. Never merge a stale SHA or assume a previous run validates a rewritten head.
- Recent Skill/runtime PRs merged include #490, #492, #493, #494, #496, #497, #498, #499, #500, #501, #502, #503, #504, #507, and #508. Reconcile each against live GitHub rather than relying on this list. PR #491 and #495 were closed without merge; do not resurrect their code blindly.
- The current work is still centered on Issue #347. PR #506 protects against a proposal containing both `toolID` and `skillID`, including when a permissive custom verifier is injected. PR #509 preserves cancellation semantics and prevents a cancelled Module action from being logged as an ordinary failed execution.
- The last observed CI evidence above is from 2026-10-17. Recheck latest Actions and branch state before making any claim.

## Immediate execution order

1. Reconcile PR #506 and #509 against current `main`; merge only if clean and all required checks pass on the exact heads. Handle overlapping M6 edits sequentially, rerunning gates after any rebase or repair.
2. Continue Issue #347 with a source-level audit of production Skill → Module/Tool execution, typed identity, effective capability union, approval propagation and denial, schema validation, cancellation, event causality, and verifier identity. Find the next uncovered defect rather than repeating merged regressions.
3. For every finding: demonstrate the gap in code/tests; create a narrowly scoped task contract; add a regression that fails before the fix; implement the smallest safe correction; validate the task and final diff; run tests; wait for all required CI workflows; inspect failures and fix them. Continue with independent audits while CI runs.
4. Update the relevant issue after each completed task. Keep the task contract and handoff current, but do not create separate commits merely for status notes.
5. Once the Skill execution path is evidenced, continue the highest-impact gaps under #354 and #367. For #429, preserve the approved animated glass Agent Orb direction, fix genuine startup “Attention Agent” failures rather than hiding them, and measure SwiftUI lag/load only what is actually visible.
6. Keep provider/GGUF behavior, local model temperature/performance, Vietnamese UI, secure credential storage, import/export, and real iPhone 12 Pro Max acceptance as explicit product validation—not as assumed complete. Verify device-specific behavior separately.

## Non-negotiable product/runtime invariants

- Skill/Module execution must go through the authorized runtime boundary; no prompt/LLM bypass, implicit broad capability grants, or model-claimed success.
- Policy denial cannot be overridden by approval. Approval errors fail closed. Bind approval to the exact typed Skill/Tool identity and actual effective capabilities.
- Unsupported, ambiguous, mismatched-schema, unconfigured, or unauthorized targets fail closed before side effects.
- Cancellation remains cancellation; do not turn it into an ordinary failed action or emit misleading execution success.
- Audit events must carry stable `goalID`, `actionID`, and the relevant typed `skillID`/`toolID`; connect execution attempts to observations without claiming execution when none occurred.
- Success requires actual execution, matching identity, and required independent verification. A receipt or executor return alone is not enough.
- Markdown is canonical human-readable persistence. Root `Modules/` is for cognitive grains; `Sources/Capabilities/Modules` is executable runtime code.
- Keep the approved architecture; no broad rewrites, unsafe model code execution, arbitrary file writes, or weakened gates.
- CI green is not physical iPhone acceptance. Record actual device evidence separately.
- Grain lifecycle: OBSERVED → CONFIRMED → PROMOTED.

## Required gates and final communication

Required repo gates are Agent Task Contract, M3, and Apple Native Build & Unsigned IPA on the exact final PR head. Read logs and fix failures; do not shrink gate scope for speed. A successful merge does not prove the app is fully beta-ready. Report to the user in short Vietnamese: what became materially safer/usable, what is next, and only a real blocker that needs their decision.
