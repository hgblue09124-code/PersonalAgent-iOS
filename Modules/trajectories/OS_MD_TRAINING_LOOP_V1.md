# OS Markdown Training Loop v1

Status: OBSERVED

This is the operational bridge from model-assisted work to persistent Agent OS learning.

It is Markdown-native. It does not add Swift, CI, a parser, an index, a database, or automatic promotion.

## Runtime loop

```
MODEL LAST
    ↓
TASK
    ↓
READ current OS state
    ↓
ACT through existing Agent OS boundaries
    ↓
VERIFY with direct evidence
    ↓
WRITE TRAJECTORY
    ↓
EXTRACT one reusable pattern
    ↓
WRITE / UPDATE Candidate Grain
    ↓
ATTACH evidence
    ↓
CONFIRM when the gate is satisfied
    ↓
PROMOTE only when earned
    ↓
PERSIST into standing OS knowledge
    ↓
NEXT TASK
```

## What each pass produces

### 1. Task

Record one concrete task.

Minimum:
- TASK
- SCOPE
- CONSTRAINT
- SOURCE

### 2. Model-assisted execution

The current strongest model may solve the task.

The model is an execution/reasoning teacher, not the durable knowledge store.

Record only observable reasoning transitions needed to reproduce the work:
- READ
- DECISION
- ACTION
- VERIFY
- RESULT

Do not copy hidden chain-of-thought or store raw model output as knowledge.

### 3. Trajectory

Append the execution evidence to:

`Documentation/LESSONS.md` (simulation-only trajectory log removed 2026-09-27; no CONFIRMED evidence)

A trajectory records what happened. It is not itself a grain.

### 4. Extraction

Ask one question:

> What reusable rule was demonstrated here that could help the OS on another task?

Create or update exactly one candidate when a bounded pattern exists.

Candidate location:

`Modules/trajectories/OS_MD_CANDIDATE_GRAINS.md`

Every candidate starts:

`STATUS: OBSERVED`

### 5. Evidence attachment

For the candidate, attach:

- exact trajectory RUN references;
- repository file/path evidence;
- commit or PR evidence when applicable;
- test/CI evidence when applicable;
- contradictory evidence, if any.

Repetition alone never confirms a grain.

### 6. Confirmation

Change:

`OBSERVED → CONFIRMED`

only when a concrete task independently demonstrates that the candidate rule works and the repository state supports the claim.

If evidence contradicts the candidate:
- keep or return it to OBSERVED;
- record the contradiction;
- revise or discard the candidate.

### 7. Promotion

Change:

`CONFIRMED → PROMOTED`

only after independent repetition or architecture-critical evidence.

Promotion writes the knowledge to its durable home:
- `Documentation/LESSONS.md` for reusable operating lessons;
- `Documentation/ARCHITECTURE.md` for architecture rules;
- `Modules/` for durable cognitive grains.

Do not promote into all surfaces by default.

## Training pass template

Use this compact record for each model-assisted pass:

```
TASK:
SCOPE:
SOURCE:

READ:
DECISION:
ACTION:
VERIFY:
RESULT:

TRAJECTORY:
CANDIDATE:
EVIDENCE:
STATUS:
NEXT:
```

## Guardrails

- One task = one logical commit.
- Preserve existing runtime boundaries.
- Evidence determines trust.
- Trajectory recurrence is a signal, not proof.
- Never skip `OBSERVED → CONFIRMED → PROMOTED`.
- Do not turn repeated Markdown into fake knowledge.
- Do not introduce retrieval infrastructure until real usage demonstrates the need.

## Current state

Existing trajectory corpus:
- RUN-001–1000

Existing extraction:
- CAND-001 — Verification-preserving minimal repair
- STATUS: OBSERVED

Therefore the next model-assisted pass should produce **one real trajectory and one evidence-backed extraction attempt**, not another bulk trajectory expansion.

## Success condition

The loop is working when a real model-assisted task can move through:

`Task → Trajectory → Candidate Grain → Evidence → CONFIRMED`

without changing the runtime and without treating model output or repetition as durable knowledge.
