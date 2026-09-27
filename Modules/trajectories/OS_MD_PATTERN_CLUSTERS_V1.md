# OS Markdown Pattern Clusters V1

Status: OBSERVED

This document is a batch extraction from the 1,000 trajectory corpus in
`Documentation/LESSONS.md` (simulation-only trajectory log removed 2026-09-27; no CONFIRMED evidence).

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

**Observed in:** RUN-001–003, RUN-007, and recurring classification runs.

**Pattern**
- Classify the task against evidence, not assumption.
- Prefer the narrowest correct class before choosing a broader action.
- Fail closed when classification evidence is insufficient.

**Candidate grain:** Evidence-first task classification.

**Status:** OBSERVED

**Confirmation gate**
- A real task must show that classification based on repository evidence
  produced a different or safer action than surface description alone.

---

### CL-003 — Minimal valid action at the failing boundary

**Observed in:** RUN-002–004, RUN-008, RUN-014–015.

**Pattern**
- Localize the failing boundary first.
- Apply the smallest valid repair at that boundary.
- Do not broaden the change merely because a wider edit is possible.

**Candidate grain:** Minimal valid repair at localized boundary.

**Status:** OBSERVED

**Confirmation gate**
- A real repair task must show the chosen diff stays within the localized
  failing boundary and still restores the intended invariant.

---

### CL-004 — Preserve the verification mechanism

**Observed in:** RUN-003, RUN-014.

**Pattern**
- Do not suppress the mechanism that exposed the defect.
- Keep tests, checks, and verification paths intact while repairing.
- Treat verification as a separate stage from execution.

**Candidate grain:** Verification-preserving repair.

**Status:** OBSERVED

**Confirmation gate**
- A real repair must leave the original verification mechanism able to detect
  regression after the fix.

---

### CL-005 — Scope-bounded change with clean attribution

**Observed in:** RUN-008 and focused migration trajectories.

**Pattern**
- Keep the final diff and commit history matched to one logical task.
- Avoid unrelated edits that increase uncertainty about the change.
- Attribute the resulting repository state to the intended task boundary.

**Candidate grain:** Scope-bounded change with clean attribution.

**Status:** OBSERVED

**Confirmation gate**
- Compare requested task, final diff, and resulting commit; unrelated changes
  must be absent or explicitly justified.

---

### CL-006 — Fail closed when evidence is insufficient

**Observed in:** RUN-007, RUN-014 and fail-closed curriculum runs.

**Pattern**
- Prefer no action or a narrower safe action over an under-evidenced claim.
- Record the missing evidence rather than inventing certainty.
- Do not promote knowledge past OBSERVED without independent support.

**Candidate grain:** Fail-closed under insufficient evidence.

**Status:** OBSERVED

**Confirmation gate**
- A real task must show that insufficient evidence correctly blocked promotion
  or broadened action.

---

### CL-007 — Extract one reusable pattern after verification

**Observed in:** RUN-015 and extraction-oriented runs.

**Pattern**
- After verification, ask what reusable rule was demonstrated.
- Create or update exactly one candidate when a bounded pattern exists.
- Keep the candidate OBSERVED until independent confirmation.

**Candidate grain:** Post-verification single-pattern extraction.

**Status:** OBSERVED

**Confirmation gate**
- A real task must produce one candidate grain whose evidence boundary is
  explicit and not based solely on corpus repetition.

---

### CL-008 — Lifecycle transitions require traceable evidence

**Observed in:** promotion-gate runs and AGENTS.md lifecycle rules.

**Pattern**
- OBSERVED → CONFIRMED requires independent concrete evidence.
- CONFIRMED → PROMOTED requires independent repetition or architecture-critical
  justification.
- Do not skip lifecycle stages.

**Candidate grain:** Evidence-gated knowledge lifecycle.

**Status:** OBSERVED

**Confirmation gate**
- A real task must move a candidate through a justified lifecycle
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
