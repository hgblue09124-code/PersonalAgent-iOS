# OS Markdown Trajectory Runs 001–085

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


---

# Curriculum Training — Runs 016–085

These runs extend the first 15 observations into seven additional curriculum levels. The purpose is progressive complexity, not model-weight fine-tuning. Every run remains `OBSERVED` unless independent repository evidence establishes a stronger lifecycle state.

## L2 — Classification

### RUN-016 — classify CI failure by exact failing boundary

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Classify CI failure by exact failing boundary using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-017 — separate test regression from production regression

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Separate test regression from production regression using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-018 — separate inherited failure from current-task failure

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Separate inherited failure from current-task failure using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-019 — classify migration contamination from code defect

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Classify migration contamination from code defect using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-020 — distinguish environment failure from source failure

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Distinguish environment failure from source failure using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-021 — classify evidence as direct or inferred

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Classify evidence as direct or inferred using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-022 — classify scope as task-local or cross-cutting

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Classify scope as task-local or cross-cutting using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-023 — separate documentation inconsistency from runtime defect

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Separate documentation inconsistency from runtime defect using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-024 — classify green execution without verification

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Classify green execution without verification using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-025 — build a failure taxonomy from concrete evidence

TYPE
- Curriculum training at L2 — Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Build a failure taxonomy from concrete evidence using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L3 — Minimal Repair

### RUN-026 — repair only the confirmed failing file

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Repair only the confirmed failing file using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-027 — restore an assertion without weakening it

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Restore an assertion without weakening it using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-028 — repair a malformed contract at its boundary

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Repair a malformed contract at its boundary using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-029 — remove unrelated diff from a focused task

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Remove unrelated diff from a focused task using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-030 — preserve existing behavior while fixing the defect

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Preserve existing behavior while fixing the defect using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-031 — add the smallest regression test for a confirmed bug

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Add the smallest regression test for a confirmed bug using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-032 — avoid broad refactor during local repair

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Avoid broad refactor during local repair using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-033 — keep one logical task in one commit

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Keep one logical task in one commit using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-034 — compare before/after diff against root cause

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Compare before/after diff against root cause using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-035 — stop after the evidence gate passes

TYPE
- Curriculum training at L3 — Minimal Repair.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Stop after the evidence gate passes using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L4 — Verification

### RUN-036 — define evidence required for a claimed fix

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Define evidence required for a claimed fix using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-037 — separate execution from verification

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Separate execution from verification using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-038 — verify a migration with diff and tests

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify a migration with diff and tests using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-039 — verify a contract change with focused tests

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify a contract change with focused tests using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-040 — verify negative behavior and fail-closed behavior

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify negative behavior and fail-closed behavior using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-041 — verify no unrelated files changed

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify no unrelated files changed using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-042 — verify CI result belongs to the exact head commit

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify CI result belongs to the exact head commit using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-043 — verify lifecycle status against evidence

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Verify lifecycle status against evidence using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-044 — reject a claim when evidence is ambiguous

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Reject a claim when evidence is ambiguous using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-045 — record an independently observable verification result

TYPE
- Curriculum training at L4 — Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Record an independently observable verification result using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L5 — Architecture

### RUN-046 — identify Kernel versus Runtime ownership

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Identify Kernel versus Runtime ownership using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-047 — identify Runtime versus Module boundary

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Identify Runtime versus Module boundary using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-048 — identify cognitive grain versus executable module

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Identify cognitive grain versus executable module using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-049 — preserve canonical layout during migration

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Preserve canonical layout during migration using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-050 — detect duplicated ownership in architecture

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Detect duplicated ownership in architecture using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-051 — compose existing grains without inventing infrastructure

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Compose existing grains without inventing infrastructure using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-052 — trace dependency direction before moving code

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Trace dependency direction before moving code using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-053 — keep Markdown persistence separate from runtime execution

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Keep Markdown persistence separate from runtime execution using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-054 — identify the correct integration boundary

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Identify the correct integration boundary using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-055 — validate architecture claims against repository structure

TYPE
- Curriculum training at L5 — Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Validate architecture claims against repository structure using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L6 — Multi-step

### RUN-056 — plan a migration as ordered evidence-preserving steps

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Plan a migration as ordered evidence-preserving steps using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-057 — combine classification repair and verification

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Combine classification repair and verification using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-058 — handle a task with multiple dependent files

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Handle a task with multiple dependent files using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-059 — preserve scope while resolving sequential failures

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Preserve scope while resolving sequential failures using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-060 — use previous evidence to choose the next gate

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Use previous evidence to choose the next gate using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-061 — maintain one logical commit across a multi-step task

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Maintain one logical commit across a multi-step task using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-062 — reconcile architecture intent with current repository reality

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Reconcile architecture intent with current repository reality using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-063 — sequence tests from cheapest to strongest useful gate

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Sequence tests from cheapest to strongest useful gate using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-064 — persist only reusable learning after the full loop

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Persist only reusable learning after the full loop using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-065 — complete Read Act Verify Learn Persist as one workflow

TYPE
- Curriculum training at L6 — Multi-step.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Complete Read Act Verify Learn Persist as one workflow using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L7 — Adversarial

### RUN-066 — handle contradictory repository signals

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Handle contradictory repository signals using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-067 — reject a plausible fix lacking evidence

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Reject a plausible fix lacking evidence using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-068 — detect a contaminated branch before repair

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Detect a contaminated branch before repair using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-069 — handle a green CI run with the wrong commit

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Handle a green CI run with the wrong commit using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-070 — resist a tempting broad refactor

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Resist a tempting broad refactor using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-071 — treat ambiguous parser or contract output as fail-closed

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Treat ambiguous parser or contract output as fail-closed using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-072 — detect when documentation and code disagree

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Detect when documentation and code disagree using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-073 — distinguish repeated inference from independent evidence

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Distinguish repeated inference from independent evidence using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-074 — reject unsupported promotion of a candidate lesson

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Reject unsupported promotion of a candidate lesson using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-075 — recover from an invalid earlier assumption using new evidence

TYPE
- Curriculum training at L7 — Adversarial.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Recover from an invalid earlier assumption using new evidence using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


## L8 — Autonomous

### RUN-076 — independently select relevant AGENTS and lesson context

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Independently select relevant AGENTS and lesson context using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-077 — choose the smallest useful cognitive grains for a task

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Choose the smallest useful cognitive grains for a task using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-078 — form an evidence-first action plan without speculative edits

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Form an evidence-first action plan without speculative edits using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-079 — execute a complete diagnose repair verify persist loop

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Execute a complete diagnose repair verify persist loop using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-080 — adapt the next action from observed verification results

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Adapt the next action from observed verification results using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-081 — maintain baseline and training lineage autonomously

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Maintain baseline and training lineage autonomously using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-082 — decide when to stop instead of expanding scope

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Decide when to stop instead of expanding scope using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-083 — produce a concise evidence-backed handoff state

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Produce a concise evidence-backed handoff state using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-084 — identify a reusable candidate lesson without premature promotion

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Identify a reusable candidate lesson without premature promotion using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

### RUN-085 — complete an autonomous OS training checkpoint

TYPE
- Curriculum training at L8 — Autonomous.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Treat the task as a bounded training problem: identify the evidence boundary first, preserve the repository's canonical architecture, and avoid converting inference into durable knowledge.
- Increase complexity only after the preceding level's discipline is preserved.

ACTION
- Complete an autonomous OS training checkpoint using the smallest evidence-backed action available.

VERIFY
- Compare the action with the exact task boundary, relevant diff/test/CI evidence, and the lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- The Agent should improve the named capability while preserving evidence-first reasoning, minimal scope, and verification before promotion.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-086 — identify the task

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify the task using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify the task while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-087 — identify the input

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify the input using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify the input while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-088 — identify the output

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify the output using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify the output while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-089 — separate fact from assumption

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- separate fact from assumption using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen separate fact from assumption while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-090 — name the missing evidence

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- name the missing evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen name the missing evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-091 — record the observed state

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- record the observed state using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen record the observed state while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-092 — avoid guessing hidden state

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid guessing hidden state using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid guessing hidden state while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-093 — state the smallest question

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state the smallest question using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state the smallest question while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-094 — preserve exact terminology

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- preserve exact terminology using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen preserve exact terminology while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-095 — close the observation cleanly

TYPE
- Curriculum training at L9 — Basic Observation.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- close the observation cleanly using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen close the observation cleanly while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-096 — classify a simple request

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a simple request using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a simple request while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-097 — classify a file change

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a file change using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a file change while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-098 — classify a test result

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a test result using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a test result while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-099 — classify a documentation change

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a documentation change using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a documentation change while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-100 — classify a runtime symptom

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a runtime symptom using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a runtime symptom while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-101 — classify a build symptom

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify a build symptom using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify a build symptom while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-102 — classify direct evidence

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify direct evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify direct evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-103 — classify inferred evidence

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify inferred evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify inferred evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-104 — classify task scope

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify task scope using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify task scope while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-105 — classify stop conditions

TYPE
- Curriculum training at L10 — Basic Classification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- classify stop conditions using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen classify stop conditions while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-106 — put steps in order

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- put steps in order using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen put steps in order while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-107 — choose the first useful check

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- choose the first useful check using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen choose the first useful check while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-108 — choose the next check from evidence

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- choose the next check from evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen choose the next check from evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-109 — avoid skipping a prerequisite

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid skipping a prerequisite using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid skipping a prerequisite while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-110 — keep a short action sequence

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- keep a short action sequence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen keep a short action sequence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-111 — stop after the required gate

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- stop after the required gate using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen stop after the required gate while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-112 — reuse the previous result

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- reuse the previous result using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen reuse the previous result while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-113 — avoid duplicate checks

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid duplicate checks using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid duplicate checks while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-114 — separate action from verification

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- separate action from verification using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen separate action from verification while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-115 — record the completed sequence

TYPE
- Curriculum training at L11 — Basic Sequencing.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- record the completed sequence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen record the completed sequence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-116 — remember a confirmed fact

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- remember a confirmed fact using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen remember a confirmed fact while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-117 — keep an observed fact provisional

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- keep an observed fact provisional using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen keep an observed fact provisional while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-118 — reuse a prior lesson

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- reuse a prior lesson using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen reuse a prior lesson while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-119 — avoid duplicating memory

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid duplicating memory using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid duplicating memory while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-120 — separate history from lesson

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- separate history from lesson using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen separate history from lesson while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-121 — preserve source evidence

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- preserve source evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen preserve source evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-122 — identify stale context

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify stale context using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify stale context while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-123 — refresh the relevant context

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- refresh the relevant context using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen refresh the relevant context while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-124 — persist only reusable knowledge

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- persist only reusable knowledge using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen persist only reusable knowledge while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-125 — keep memory concise

TYPE
- Curriculum training at L12 — Basic Memory.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- keep memory concise using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen keep memory concise while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-126 — define task boundaries

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- define task boundaries using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen define task boundaries while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-127 — list in-scope items

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- list in-scope items using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen list in-scope items while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-128 — list out-of-scope items

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- list out-of-scope items using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen list out-of-scope items while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-129 — avoid unrelated edits

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid unrelated edits using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid unrelated edits while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-130 — detect scope expansion

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- detect scope expansion using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen detect scope expansion while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-131 — return to the original task

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- return to the original task using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen return to the original task while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-132 — compare change with task intent

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- compare change with task intent using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen compare change with task intent while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-133 — keep one logical change

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- keep one logical change using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen keep one logical change while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-134 — stop before speculative cleanup

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- stop before speculative cleanup using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen stop before speculative cleanup while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-135 — summarize final scope

TYPE
- Curriculum training at L13 — Basic Scope.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- summarize final scope using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen summarize final scope while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-136 — verify a file exists

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify a file exists using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify a file exists while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-137 — verify a change is present

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify a change is present using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify a change is present while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-138 — verify a change is absent

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify a change is absent using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify a change is absent while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-139 — verify the expected output

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify the expected output using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify the expected output while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-140 — verify a negative case

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify a negative case using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify a negative case while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-141 — verify the exact revision

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify the exact revision using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify the exact revision while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-142 — verify the relevant test

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify the relevant test using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify the relevant test while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-143 — verify evidence belongs to the task

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify evidence belongs to the task using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify evidence belongs to the task while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-144 — reject ambiguous evidence

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- reject ambiguous evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen reject ambiguous evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-145 — record the verification result

TYPE
- Curriculum training at L14 — Basic Verification.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- record the verification result using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen record the verification result while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-146 — identify Kernel ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify Kernel ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify Kernel ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-147 — identify Runtime ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify Runtime ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify Runtime ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-148 — identify Module ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify Module ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify Module ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-149 — identify storage ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify storage ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify storage ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-150 — identify interface ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- identify interface ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen identify interface ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-151 — separate cognitive data from code

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- separate cognitive data from code using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen separate cognitive data from code while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-152 — preserve dependency direction

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- preserve dependency direction using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen preserve dependency direction while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-153 — avoid duplicate ownership

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid duplicate ownership using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid duplicate ownership while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-154 — use the canonical location

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- use the canonical location using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen use the canonical location while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-155 — describe the boundary simply

TYPE
- Curriculum training at L15 — Basic Architecture.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- describe the boundary simply using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen describe the boundary simply while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-156 — recover from a wrong assumption

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- recover from a wrong assumption using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen recover from a wrong assumption while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-157 — recover from a failed check

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- recover from a failed check using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen recover from a failed check while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-158 — recover from stale information

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- recover from stale information using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen recover from stale information while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-159 — recover from an unrelated error

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- recover from an unrelated error using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen recover from an unrelated error while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-160 — recover without broad refactoring

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- recover without broad refactoring using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen recover without broad refactoring while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-161 — return to the last known good state

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- return to the last known good state using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen return to the last known good state while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-162 — re-check the exact boundary

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- re-check the exact boundary using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen re-check the exact boundary while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-163 — choose the smallest corrective action

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- choose the smallest corrective action using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen choose the smallest corrective action while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-164 — verify recovery

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- verify recovery using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen verify recovery while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-165 — persist the reusable recovery rule

TYPE
- Curriculum training at L16 — Basic Recovery.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- persist the reusable recovery rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen persist the reusable recovery rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-166 — state the current state

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state the current state using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state the current state while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-167 — state the exact blocker

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state the exact blocker using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state the exact blocker while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-168 — state the evidence

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state the evidence using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state the evidence while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-169 — state what changed

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state what changed using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state what changed while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-170 — state what did not change

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- state what did not change using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen state what did not change while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-171 — give a concise handoff

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- give a concise handoff using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen give a concise handoff while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-172 — avoid unsupported claims

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- avoid unsupported claims using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen avoid unsupported claims while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-173 — separate fact from interpretation

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- separate fact from interpretation using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen separate fact from interpretation while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-174 — name the next gate

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- name the next gate using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen name the next gate while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-175 — close the report

TYPE
- Curriculum training at L17 — Basic Communication.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- close the report using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen close the report while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-176 — repeat an evidence-first pattern

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- repeat an evidence-first pattern using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen repeat an evidence-first pattern while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-177 — apply a rule to a new simple topic

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- apply a rule to a new simple topic using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen apply a rule to a new simple topic while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-178 — generalize a boundary rule

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- generalize a boundary rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen generalize a boundary rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-179 — generalize a verification rule

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- generalize a verification rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen generalize a verification rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-180 — generalize a scope rule

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- generalize a scope rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen generalize a scope rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-181 — generalize a memory rule

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- generalize a memory rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen generalize a memory rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-182 — generalize an architecture rule

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- generalize an architecture rule using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen generalize an architecture rule while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-183 — detect a repeated pattern

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- detect a repeated pattern using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen detect a repeated pattern while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-184 — keep the pattern OBSERVED without proof

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- keep the pattern OBSERVED without proof using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen keep the pattern OBSERVED without proof while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.


### RUN-185 — complete a small generalization checkpoint

TYPE
- Curriculum training at L18 — Repetition and Generalization.

READ
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant Markdown OS / Cognitive Ocean contracts.
- Repository evidence directly related to the task.

REASON
- Start from concrete evidence, keep the task small, preserve canonical architecture, and do not convert inference into durable knowledge.
- This round is intentionally simple and repetitive so the Agent can strengthen the named behavior before increasing task complexity.

ACTION
- complete a small generalization checkpoint using the smallest evidence-backed action available.

VERIFY
- Check the exact task boundary, the observable result, and the applicable lifecycle rules in AGENTS.md and Documentation/LESSONS.md.

LEARN
- Strengthen complete a small generalization checkpoint while preserving evidence-first reasoning, minimal scope, verification, and fail-closed behavior.

STATUS: OBSERVED

SOURCE
- AGENTS.md.
- Documentation/LESSONS.md.
- Relevant repository state and applicable evidence.

