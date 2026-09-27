# OS Markdown Flow Simulation V1

Status: SIMULATED

Purpose: exercise the OS Markdown learning loop end-to-end with small,
controlled tasks before using it on real repository changes.

These are simulations only. Their results are not repository evidence and
must not promote any grain.

## Simulation contract

Flow under test:

TASK → READ → ACT → VERIFY → TRAJECTORY → PATTERN → CANDIDATE → EVIDENCE
→ CONFIRM/PRESERVE OBSERVED → PERSIST

Rules exercised:
- read current state before action;
- classify before repair;
- keep the smallest scope;
- separate action from verification;
- distinguish trajectory from grain;
- require independent evidence for CONFIRMED;
- keep Markdown canonical while no retrieval bottleneck is demonstrated.

## SIM-001 — classify before repair

**Task**
- A hypothetical test failure appears after a one-file change.

**READ**
- AGENTS.md
- current diff
- failing test output

**DECISION**
- Treat the failure as task-local only if the diff and failure location support
  that conclusion.

**ACTION**
- No repair until the failing boundary is localized.

**VERIFY**
- Simulated evidence agrees with the changed file and failure location.

**RESULT**
- PASS — classification gate works.

**PATTERN**
- Evidence-first classification.

**CANDIDATE**
- CL-002.

**EVIDENCE**
- Simulation evidence only.

**STATUS**
- OBSERVED — no confirmation.

---

## SIM-002 — minimal repair

**Task**
- A hypothetical assertion has an incorrect argument type.

**READ**
- changed test file
- compiler diagnostic
- surrounding assertion contract

**DECISION**
- Repair the assertion at the failing test boundary.

**ACTION**
- Change only the invalid argument.

**VERIFY**
- Simulated test passes and the assertion remains present.

**RESULT**
- PASS — minimal repair preserves the verification surface.

**PATTERN**
- Verification-preserving minimal repair.

**CANDIDATE**
- CL-003 / CAND-001.

**EVIDENCE**
- Simulation evidence only.

**STATUS**
- OBSERVED — no confirmation.

---

## SIM-003 — execution is not verification

**Task**
- A hypothetical migration command completes successfully.

**READ**
- intended invariant
- resulting repository state

**DECISION**
- Do not mark success from process exit alone.

**ACTION**
- Inspect the resulting state against the invariant.

**VERIFY**
- Simulated state matches the intended invariant.

**RESULT**
- PASS — execution and verification remain separate.

**PATTERN**
- Independent verification gate.

**CANDIDATE**
- CL-005.

**EVIDENCE**
- Simulation evidence only.

**STATUS**
- OBSERVED — no confirmation.

---

## SIM-004 — trajectory versus grain

**Task**
- Three simulated tasks exhibit the same repair behavior.

**READ**
- their task context, actions, verification, and results

**DECISION**
- Repetition is sufficient to propose a candidate pattern, not to promote it.

**ACTION**
- Keep the runs as trajectories and create one bounded candidate.

**VERIFY**
- Candidate has explicit scope and provenance.

**RESULT**
- PASS — trajectory remains training material; candidate remains OBSERVED.

**PATTERN**
- Trajectory-to-grain separation.

**CANDIDATE**
- CL-007.

**EVIDENCE**
- Simulation evidence only.

**STATUS**
- OBSERVED — no confirmation.

---

## SIM-005 — evidence gate blocks false promotion

**Task**
- A candidate appears repeatedly in simulated runs but no real repository task
  independently demonstrates it.

**READ**
- candidate status
- trajectory references
- evidence boundary

**DECISION**
- Do not promote.

**ACTION**
- Keep candidate at OBSERVED.

**VERIFY**
- Promotion gate rejects simulation-only evidence.

**RESULT**
- PASS — false promotion is blocked.

**PATTERN**
- Evidence-backed lifecycle promotion.

**CANDIDATE**
- CL-008.

**EVIDENCE**
- Simulation evidence only.

**STATUS**
- OBSERVED — correctly not promoted.

---

## Flow result

| Stage | Result |
|---|---|
| TASK | PASS |
| READ | PASS |
| ACT | PASS |
| VERIFY | PASS |
| TRAJECTORY | PASS |
| PATTERN extraction | PASS |
| CANDIDATE creation | PASS |
| Evidence boundary | PASS |
| False-promotion guard | PASS |
| CONFIRMED | NOT EARNED |
| PROMOTED | NOT EARNED |
| Persistence | PASS |

### Simulation score

- Scenarios: **5**
- Flow stages exercised: **10**
- Simulated stage failures: **0**
- False promotions: **0**
- CONFIRMED grains: **0**
- PROMOTED grains: **0**
- Real repository evidence produced: **0**

## What this proves

The Markdown design can represent the complete learning flow without adding
Swift runtime code, a parser, an index, a database, or automatic promotion.

It does **not** prove that the extracted rules work on real repository tasks.

The first real-task pass should use one cluster, perform an actual bounded task,
capture the resulting evidence, and attempt one genuine lifecycle transition.
