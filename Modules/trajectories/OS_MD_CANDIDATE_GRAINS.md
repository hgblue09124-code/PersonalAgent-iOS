# OS Markdown Candidate Grains

Status: OBSERVED

This ledger is the first concrete extraction artifact between trajectory data and the Living Cognitive Data Ocean.

It does not promote a grain. It records one candidate, its trajectory evidence, its external repository evidence, and the exact gate still required for confirmation.

## CAND-001 — Verification-preserving minimal repair

STATUS: OBSERVED

PURPOSE
- Identify a reusable repair rule from observed trajectories without treating repetition as proof.

WHEN
- A task has a localized failure or defect and a repair is being considered.

CANDIDATE KNOWLEDGE
- Once the failing boundary is localized, make the smallest valid repair at that boundary.
- Preserve the verification mechanism that establishes the intended invariant.
- Verify the resulting repository state with evidence appropriate to the claim.
- Do not broaden the repair merely because a wider change is possible.

TRAJECTORY EVIDENCE
- RUN-002 — The current-task test regression is repaired at the test boundary rather than by changing unrelated CI, architecture, or Markdown.
- RUN-003 — A repair is incomplete when it only suppresses the mechanism that exposed the defect; the verification boundary must remain intact.
- RUN-008 — After localization, unrelated edits increase uncertainty; the repair should stay within the confirmed failing boundary.
- RUN-014 — Execution and verification are separate stages; completion requires an independent observable result.
- RUN-015 — These patterns recur across the first training batch but remain OBSERVED until independently established.

EXTERNAL REPOSITORY EVIDENCE
- Documentation/LESSONS.md, L-002: a focused migration must be built from the current main commit and its changed files/history must match the single logical task.
- AGENTS.md: One Task = One Logical Commit.
- AGENTS.md: lessons become CONFIRMED only after concrete code, test, or CI evidence.

EVIDENCE BOUNDARY
- The trajectory records establish recurrence of the pattern.
- L-002 independently establishes the minimal-scope/clean-lineage side of the rule.
- This ledger does not claim that every occurrence in RUN-001–1000 is independent evidence.

CONFIRMATION GATE
- Confirm only after a new repository task independently demonstrates the same rule with concrete code, test, CI, or verified repository-state evidence.
- If the new evidence contradicts the candidate, revise or discard the candidate rather than promoting it.

SOURCE
- Modules/trajectories/OS_MD_TRAJECTORY_RUNS_001_005.md
- Documentation/LESSONS.md
- AGENTS.md

## Extraction rule

1. Start from observed trajectories.
2. Select a repeated behavior that has a bounded meaning.
3. Attach exact trajectory references.
4. Attach independent repository evidence when available.
5. Keep status OBSERVED until the confirmation gate is satisfied.
6. Promote only after the lifecycle rule in AGENTS.md is met.

This is intentionally Markdown-native. No parser, index, database, or automatic promotion engine is introduced.
