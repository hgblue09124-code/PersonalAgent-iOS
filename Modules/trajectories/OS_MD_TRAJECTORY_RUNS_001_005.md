# OS Markdown Trajectory Runs 001–005

Status: OBSERVED

This file records five real OS Markdown reasoning runs performed against the current PersonalAgent-iOS repository state. These are trajectory observations, not claims of successful code repair. They preserve context, selected cognitive grains, decision, evidence boundary, and learning produced by each run.

The file is intentionally Markdown-native. It does not introduce a rigid training schema, parser, index, or database.

## RUN-001 — CI failure classification

TYPE
- Diagnose a CI failure before changing code.

READ
- AGENTS.md
- Documentation/LESSONS.md
- Documentation/PERSONAL_AGENT_OS_MARKDOWN.md
- Documentation/LIVING_COGNITIVE_DATA_OCEAN.md
- CI/test evidence for the affected commit.

REASON
- A CI failure must first be localized to the exact commit and changed file.
- Do not infer an architecture defect from a test failure alone.
- Do not change unrelated production code.

ACTION
- Classify the failure as task-local or inherited before proposing repair.

VERIFY
- Compare failing commit, diff, compiler/test output, and relevant CI run.

LEARN
- CI repair begins with evidence localization, not speculative repair.

STATUS: OBSERVED

SOURCE
- Current repository operating rules and Markdown OS product contracts.

---

## RUN-002 — Acceptance-test failure geometry

TYPE
- Trace a compile failure to the change that introduced it.

READ
- PR #104 history.
- Commit `1f367a531069cc5216d466867ec5b0a3883a8820`.
- `Tests/PersonalAgentTests/PersonalAgentOSLevelBTests.swift`.
- M3 CI failure for the acceptance-test commit.

OBSERVATION
- The new acceptance test introduced a Swift Testing compile error at an assertion using a String as the diagnostic argument.

REASON
- The failing file was introduced by the current task.
- The Markdown changes from the preceding commit were not the immediate source of this compile failure.

ACTION
- Keep the repair scoped to the acceptance test rather than changing CI, architecture, or unrelated Markdown.

VERIFY
- Re-run the affected Swift test/CI gate after the minimal test repair.

LEARN
- A current-task test regression should be repaired at the test boundary before considering broader repository changes.

STATUS: OBSERVED

SOURCE
- PR #104.
- Commit `1f367a531069cc5216d466867ec5b0a3883a8820`.
- M3 failure reported for that commit.

---

## RUN-003 — Verification-preserving repair

TYPE
- Derive a reusable repair pattern from observed CI work.

READ
- Grain `g093-integrity-assertions`.
- Grain `g095-migration-gate`.
- Grain `g098-durable-lessons`.
- Documentation/LESSONS.md.

REASON
- Removing or weakening a check can make CI green without restoring the intended verification boundary.
- A valid repair must preserve the evidence surface.

ACTION
- Prefer the smallest repair that restores the intended assertion/contract.

VERIFY
- Compare the affected gate before and after the repair.
- Require the resulting CI evidence to pass.

LEARN
- A repair is incomplete if it only suppresses the mechanism that exposed the defect.

CANDIDATE GRAIN
- Verification-preserving repair.

STATUS: OBSERVED

SOURCE
- Existing confirmed grains `g093-integrity-assertions`, `g095-migration-gate`, and `g098-durable-lessons`.

---

## RUN-004 — Cognitive Module composition

TYPE
- Compose a task-specific reasoning module from existing grains.

READ
- `g086-structural-only-migration`
- `g089-migration-gate`
- `g093-current-reality`
- `g095-migration-gate`
- `g098-durable-lessons`

REASON
- No single grain contains the complete migration workflow.
- The smallest useful module is a composition of independently useful grains relevant to the current task.

ACTION
- Compose: establish ownership; perform physical migration; preserve behavior; run verification gate; audit actual repository state; persist reusable evidence.

VERIFY
- Every composed rule must point back to a concrete grain and its source evidence.

LEARN
- A Cognitive Module can be formed at reasoning time without introducing a new executable module or rigid storage schema.

STATUS: OBSERVED

SOURCE
- `Modules/evidence/REAL_GRAIN_SET_30.md` and its expanded 100-grain corpus.

---

## RUN-005 — Trajectory as OS training data

TYPE
- Persist the behavior of the reasoning loop itself.

READ
- Personal Agent OS Markdown product loop: Read → Act → Verify → Learn → Persist.
- Living Cognitive Data Ocean lifecycle: OBSERVED → CONFIRMED → PROMOTED.
- Runs 001–004 above.

REASON
- Knowledge grains describe what the Agent can rely on.
- Operational Markdown describes persistent OS state.
- A trajectory records how the Agent moved from observation to decision, action, verification, and learning.

ACTION
- Persist this run as an OBSERVED trajectory rather than promoting a new permanent rule.

VERIFY
- Keep every factual claim tied to repository evidence.
- Do not mark the trajectory as CONFIRMED merely because the reasoning is plausible.

LEARN
- The OS can accumulate behavioral training material without fine-tuning the model and without replacing Markdown with a database.

STATUS: OBSERVED

SOURCE
- Documentation/PERSONAL_AGENT_OS_MARKDOWN.md
- Documentation/LIVING_COGNITIVE_DATA_OCEAN.md
- Repository history and the evidence-backed grain corpus.

---

## Data boundary

These five runs are observations of the Agent reasoning process. They are not claims that all proposed repairs were executed successfully. A future run may promote or revise a pattern only after independent code, test, or CI evidence.

The canonical persistence surface remains Markdown.

---

## RUN-006 — Baseline lineage integrity

TYPE
- Preserve the distinction between baseline and training data.

READ
- PR #104 as the pre-training snapshot.
- PR #105 as the first training-data PR.
- Current PR #105 training-lineage note.

REASON
- A training dataset is more useful when its source state is explicit.
- Mixing baseline documentation and generated trajectories would make later comparisons ambiguous.

ACTION
- Keep #104 immutable as the BASE reference and continue trajectory accumulation in #105.

VERIFY
- Confirm #105 explicitly points to #104 as its baseline.
- Keep new trajectory entries in the training-data file.

LEARN
- Training lineage should identify the exact baseline from which observations were generated.

STATUS: OBSERVED

SOURCE
- PR #104 and PR #105 repository state.

---

## RUN-007 — Evidence boundary before promotion

TYPE
- Decide whether an observed reasoning pattern is ready for durable lesson promotion.

READ
- Documentation/LESSONS.md.
- Runs 001–006.
- Grain lifecycle: OBSERVED → CONFIRMED → PROMOTED.

REASON
- Repeated reasoning is not the same as independently verified repository evidence.
- Promotion without a concrete test, code result, or CI result would turn inference into false durable memory.

ACTION
- Keep the new trajectory observations at OBSERVED.
- Promote only when independent repository evidence establishes the pattern.

VERIFY
- Require a concrete commit, test result, or CI run before changing lifecycle state.

LEARN
- Training accumulation and knowledge promotion are separate operations.

STATUS: OBSERVED

SOURCE
- AGENTS.md and Documentation/LESSONS.md.

---

## RUN-008 — Minimal-change discipline

TYPE
- Select the smallest valid action when a defect is localized.

READ
- AGENTS.md one-task/one-commit rule.
- RUN-001 and RUN-002.
- Documentation/LESSONS.md.

REASON
- Once the failing boundary is known, unrelated edits increase uncertainty and contaminate the evidence.
- A broad repair makes it harder to attribute a later green CI result.

ACTION
- Restrict the repair to the confirmed failing boundary and keep one logical task in one commit.

VERIFY
- Compare the final diff against the diagnosed failure.
- Reject unrelated file changes.

LEARN
- Minimal scope is part of the verification strategy, not merely a style preference.

STATUS: OBSERVED

SOURCE
- AGENTS.md and PR #104 failure analysis.

---

## RUN-009 — Markdown as persistent state

TYPE
- Use Markdown as the canonical cognitive persistence surface.

READ
- Documentation/PERSONAL_AGENT_OS_MARKDOWN.md.
- Documentation/HANDOFF.md.
- Documentation/WORK_LOG.md.
- Current trajectory file.

REASON
- Different Markdown surfaces have different responsibilities.
- A trajectory should record reasoning behavior without becoming a duplicate handoff or work diary.

ACTION
- Keep trajectory data under Modules/trajectories and preserve the existing operational surfaces for their original roles.

VERIFY
- Check that the trajectory records reasoning transitions and evidence boundaries rather than copying full execution history.

LEARN
- Persistence quality depends on keeping cognitive surfaces complementary.

STATUS: OBSERVED

SOURCE
- AGENTS.md and current Markdown OS documentation.

---

## RUN-010 — Grain versus trajectory

TYPE
- Separate reusable knowledge from observed agent behavior.

READ
- Documentation/LIVING_COGNITIVE_DATA_OCEAN.md.
- Existing evidence grain corpus.
- Runs 003–005.

REASON
- A grain answers what reusable knowledge/capability exists.
- A trajectory answers how the agent applied context and moved through a task.

ACTION
- Keep reusable rules in the grain/lesson surfaces and store application traces in trajectories.

VERIFY
- A candidate grain must have its own boundary and evidence.
- A trajectory must retain the contextual reasoning path and verification boundary.

LEARN
- Conflating grains with trajectories would lose the distinction between learned knowledge and behavioral training material.

STATUS: OBSERVED

SOURCE
- Living Cognitive Data Ocean model and current trajectory corpus.

---

## RUN-011 — Training without fine-tuning

TYPE
- Evaluate whether the OS can accumulate useful training material without modifying model weights.

READ
- Personal Agent OS Markdown loop.
- Runs 001–010.
- Current trajectory corpus.

REASON
- The repository already captures persistent state, reusable grains, and observed reasoning traces.
- These traces can be replayed, compared, filtered, or later transformed into training datasets without requiring immediate fine-tuning.

ACTION
- Continue collecting high-integrity trajectories before introducing a training pipeline.

VERIFY
- Preserve source context, evidence, lifecycle status, and lineage for each run.

LEARN
- Externalized cognitive traces can form a training substrate before any model-training infrastructure is introduced.

STATUS: OBSERVED

SOURCE
- Current repository Markdown OS design and trajectory records.

---

## RUN-012 — Avoid premature training schema

TYPE
- Decide whether trajectory data requires a rigid schema, parser, or database.

READ
- AGENTS.md Living Cognitive Data Ocean rules.
- Current trajectory file.
- Runs 005, 009, and 011.

REASON
- The repository explicitly defers parser/index/database work until real retrieval needs appear.
- Ten additional observations increase evidence volume but do not by themselves prove a concrete retrieval bottleneck.

ACTION
- Continue with Markdown-native trajectories.
- Do not introduce a parser, index, database, or rigid schema yet.

VERIFY
- Record the trajectories as human-readable Markdown.
- Revisit infrastructure only when a demonstrated usage problem requires it.

LEARN
- More data alone is not sufficient evidence for premature infrastructure.

STATUS: OBSERVED

SOURCE
- AGENTS.md and Documentation/LIVING_COGNITIVE_DATA_OCEAN.md.

---

## RUN-013 — Replayability of a trajectory

TYPE
- Test whether a recorded reasoning run contains enough context to be useful later.

READ
- Runs 001–012.
- Their READ, REASON, ACTION, VERIFY, LEARN, STATUS, and SOURCE sections.

REASON
- A training trajectory should retain enough context to reconstruct why an action was selected without pretending that every internal thought is recoverable.

ACTION
- Preserve concise decision-relevant context: inputs read, evidence boundary, selected action, verification rule, and resulting lesson.

VERIFY
- Each run should point to repository artifacts or explicit operating rules.
- Avoid unsupported claims about hidden model state.

LEARN
- Useful trajectory data is decision-and-evidence oriented rather than a transcript of private reasoning.

STATUS: OBSERVED

SOURCE
- Current trajectory corpus and repository evidence rules.

---

## RUN-014 — Independent verification gate

TYPE
- Distinguish successful execution from verified success.

READ
- RUN-003.
- Documentation/LESSONS.md.
- Existing verification-oriented grains.

REASON
- An action can execute without proving that the intended invariant holds.
- Verification requires an independent observable result tied to the claimed outcome.

ACTION
- Treat execution and verification as separate trajectory stages.
- Record the exact evidence required before changing a status.

VERIFY
- Require test, CI, diff, or other concrete repository evidence appropriate to the claim.

LEARN
- The training signal should reward evidence-backed completion, not merely attempted action.

STATUS: OBSERVED

SOURCE
- Existing repository verification rules and RUN-003.

---

## RUN-015 — Ten-round training checkpoint

TYPE
- Consolidate the second training batch without promoting unsupported knowledge.

READ
- Runs 006–014.
- PR #105 lineage.
- AGENTS.md and Documentation/LESSONS.md.

REASON
- The new batch repeatedly reinforces several candidate patterns: baseline lineage, evidence boundaries, minimal scope, complementary Markdown surfaces, grain/trajectory separation, and verification before promotion.
- Repetition alone does not satisfy the repository's CONFIRMED/PROMOTED evidence requirements.

ACTION
- Persist this batch as OBSERVED training data under PR #105.
- Do not modify LESSONS.md or promote any candidate pattern yet.

VERIFY
- Confirm all ten runs remain traceable to repository rules or existing evidence.
- Keep PR #105 as the training lineage for this first batch.

LEARN
- Repeated trajectory observations can strengthen a candidate training signal while preserving a strict separation between observation and durable knowledge.

STATUS: OBSERVED

SOURCE
- PR #105.
- Runs 001–014.
- AGENTS.md.
- Documentation/LESSONS.md.
