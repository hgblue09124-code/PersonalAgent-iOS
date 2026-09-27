# OS Markdown Pattern Clusters V1

Status: OBSERVED

This document is a batch extraction from the 1,000 trajectory corpus in
`Modules/trajectories/OS_MD_TRAJECTORY_RUNS_001_005.md`.

The corpus is training material, not durable knowledge by itself. Recurrence is
a signal for extraction, not independent proof. Every cluster below therefore
remains OBSERVED until a real repository task supplies independent evidence.

## Corpus metrics

| Metric | Value |
|---|---:|
| Trajectory runs | 1,000 |
| Corpus lines | 32,789 |
| Corpus characters | ~1.02M |
| Lifecycle status | 1,000 OBSERVED |
| Curriculum levels | 35 (L2–L36), plus the initial 001–015 set |
| Runs 001–015 | 15 concrete initial observations |
| Runs 016–085 | 70 progressive classification/repair/verification/architecture observations |
| Runs 086–185 | 100 basic training runs |
| Runs 186–1000 | 815 extended basic-autonomy runs |
| Distinct ACTION strings observed | 231 |
| “evidence” occurrences | 5,212 |
| “verify” occurrences | 1,045 |
| “minimal” occurrences | 1,000 |
| “scope” occurrences | 1,112 |
| “boundary” occurrences | 1,211 |
| “canonical” occurrences | 1,034 |
| “CI” occurrences | 181 |
| “grain” occurrences | 17 |

These lexical counts are corpus-shape indicators only. They do not mean a
pattern is correct, independent, or promoted.

## Extraction rule

1. Group repeated behavior by a bounded capability.
2. Keep exact RUN references as provenance.
3. Separate trajectory recurrence from repository evidence.
4. Create a candidate grain only when the behavior is reusable outside one run.
5. Keep the candidate OBSERVED until a real task independently verifies it.
6. Promote only through the existing OBSERVED → CONFIRMED → PROMOTED lifecycle.

## Cluster map

### CL-001 — Read current state before acting

**Observed in:** RUN-001, RUN-006–015, and recurring later curriculum runs.

**Pattern**
- Read AGENTS.md and relevant operational/architecture state.
- Identify the exact task, input, scope, boundary, and evidence before acting.
- Avoid action based only on the user's surface description or a remembered state.

**Candidate grain:** Current-state inspection before action.

**Status:** OBSERVED

**Confirmation gate**
- A real repository task must show that current-state inspection changed or
  constrained the chosen action, with concrete repository evidence.

---

### CL-002 — Evidence-first classification

**Observed in:** RUN-001–003, RUN-007, RUN-014–015, and L2 classification runs.

**Pattern**
- Localize the failure or task boundary before selecting a repair.
- Distinguish direct evidence from inference.
- Classify inherited/current-task, test/production, environment/source, and
  other failure boundaries before changing code.

**Candidate grain:** Evidence-first task/failure classification.

**Status:** OBSERVED

**Confirmation gate**
- A real failure must be classified from commit/diff/test/CI evidence and the
  classification must constrain the repair.

---

### CL-003 — Verification-preserving minimal repair

**Observed in:** RUN-002, RUN-003, RUN-008, RUN-014–015 and minimal-repair curriculum.

**Pattern**
- Once the failing boundary is localized, repair the smallest valid boundary.
- Preserve the mechanism that proves the intended invariant.
- Do not make CI green by deleting, weakening, or bypassing verification.

**Candidate grain:** Verification-preserving minimal repair.

**Status:** OBSERVED

**Existing candidate:** CAND-001 in
`Modules/trajectories/OS_MD_CANDIDATE_GRAINS.md`.

**Confirmation gate**
- A new repository task must demonstrate the same rule through concrete code,
  test, CI, or verified repository state.

---

### CL-004 — Scope and one-logical-commit discipline

**Observed in:** RUN-008, RUN-015 and recurring curriculum runs.

**Pattern**
- Keep the change inside the confirmed task boundary.
- Reject unrelated edits.
- Preserve the AGENTS.md one-task/one-logical-commit rule.

**Candidate grain:** Scope-bounded change with clean attribution.

**Status:** OBSERVED

**Confirmation gate**
- Compare requested task, final diff, and resulting commit; unrelated changes
  must be absent or explicitly justified.

---

### CL-005 — Separate execution from verification

**Observed in:** RUN-003, RUN-007, RUN-014–015 and verification curriculum.

**Pattern**
- Performing an action is not evidence that the intended invariant holds.
- Verification must be an observable gate appropriate to the claim.
- Status changes follow evidence, not confidence.

**Candidate grain:** Independent verification gate.

**Status:** OBSERVED

**Confirmation gate**
- A real task must have an explicit verification result independent of the
  action that produced the state.

---

### CL-006 — Preserve canonical ownership and boundaries

**Observed in:** RUN-004, RUN-009–010 and architecture curriculum.

**Pattern**
- Put reusable knowledge in the appropriate cognitive-data surface.
- Keep trajectories as behavioral training material.
- Keep executable capabilities under runtime/module boundaries.
- Do not use Markdown to bypass Kernel, Runtime, Composition, or Policy.

**Candidate grain:** Canonical ownership before persistence or composition.

**Status:** OBSERVED

**Confirmation gate**
- A concrete architecture change must demonstrate that the chosen location
  preserves ownership and runtime boundaries.

---

### CL-007 — Trajectory is not a grain

**Observed in:** RUN-005, RUN-009–011, RUN-013 and current learning-loop docs.

**Pattern**
- Trajectory records context, decision, action, verification, and learning.
- Grain records reusable knowledge/capability.
- Repetition in trajectories creates a candidate signal; it does not itself
  create durable knowledge.

**Candidate grain:** Trajectory-to-grain separation.

**Status:** OBSERVED

**Confirmation gate**
- Extract a candidate from multiple trajectories and independently verify it
  before changing lifecycle state.

---

### CL-008 — Evidence-backed lifecycle promotion

**Observed in:** RUN-007, RUN-011, RUN-015 and lifecycle curriculum.

**Pattern**
- OBSERVED is the default state for extracted training patterns.
- CONFIRMED requires concrete independent evidence.
- PROMOTED requires the repository's promotion conditions.
- Contradictory evidence revises or discards the candidate.

**Candidate grain:** Evidence-gated knowledge promotion.

**Status:** OBSERVED

**Confirmation gate**
- At least one real task must move a candidate through a justified lifecycle
  transition with traceable source evidence.

---

### CL-009 — Markdown remains the canonical persistence surface until need is proven

**Observed in:** RUN-009, RUN-012 and the Markdown OS contracts.

**Pattern**
- Use human-readable Markdown while it remains sufficient.
- Do not introduce parser/index/database infrastructure merely because the
  corpus became large.
- Introduce retrieval infrastructure only when a concrete usage problem is
  demonstrated.

**Candidate grain:** Need-driven persistence infrastructure.

**Status:** OBSERVED

**Confirmation gate**
- Demonstrate an actual retrieval/maintenance bottleneck that Markdown alone
  cannot satisfy, then introduce only the smallest required mechanism.

---

### CL-010 — Replayable, evidence-oriented trajectory

**Observed in:** RUN-005, RUN-011, RUN-013–015.

**Pattern**
- Preserve task, scope, source, decision, action, verification, result,
  trajectory, candidate, evidence, status, and next step.
- Record observable decision transitions rather than hidden/private model
  reasoning.
- Preserve provenance so a later agent can inspect and replay the evidence
  boundary.

**Candidate grain:** Evidence-oriented trajectory recording.

**Status:** OBSERVED

**Confirmation gate**
- A later task should be able to reconstruct why an action was selected and
  what evidence justified its result without requiring hidden model state.

## Batch conclusion

The 1,000-run corpus is useful as a **pattern-mining substrate**. Its strongest
signal is not the volume itself; it is the recurrence of a small set of bounded
behaviors:

**inspect → classify → minimize → preserve verification → verify → extract →
evidence-gate → persist**

The next learning boundary is therefore no longer “record more runs”. It is:

**Pattern Cluster → Candidate Grain → independent real-task evidence → CONFIRMED → PROMOTED**

The corpus should not be treated as 1,000 independent proofs. The later runs
are deliberately repetitive curriculum material, so their main value is
reinforcement and pattern discovery.

## Next concrete use

For the next real repository task, select one cluster before acting. Record:

- cluster ID used;
- exact repository evidence;
- action constrained by the cluster;
- verification result;
- contradiction, if any;
- whether the candidate remains OBSERVED or earns CONFIRMED.

No parser, index, database, automatic promotion engine, or model fine-tuning is
required for this step.
