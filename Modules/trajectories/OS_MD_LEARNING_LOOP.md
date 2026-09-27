# OS Markdown Learning Loop

Status: OBSERVED

This is the first concrete learning boundary between OS Markdown trajectories and the Living Cognitive Data Ocean.

It does not change the runtime, introduce a parser, or promote unverified knowledge.

## Purpose

Turn accumulated trajectories into a controlled path for Agent OS learning:

```
Trajectory
    ↓
Pattern extraction
    ↓
Candidate Grain
    ↓
Evidence check
    ↓
CONFIRMED
    ↓
PROMOTED
    ↓
Standing OS knowledge / architecture
```

The important boundary is that **trajectory is evidence of behavior, not knowledge by itself**.

## Step 1 — Observe

Record the trajectory with:
- task/context;
- READ;
- REASON;
- ACTION;
- VERIFY;
- LEARN;
- STATUS;
- SOURCE.

A trajectory remains `OBSERVED` until a reusable pattern is identified and independently supported.

## Step 2 — Extract

Look across multiple trajectories for a repeated rule that is:
- semantically stable;
- independently useful;
- bounded;
- supported by concrete evidence.

Do not promote a statement merely because it appears many times.

Repetition is a signal for extraction, not proof.

## Step 3 — Candidate Grain

A candidate grain records the proposed reusable knowledge without changing the trusted Ocean.

Minimum meaning:

```
ID
PURPOSE
WHEN
RULE / KNOWLEDGE
VERIFY
STATUS: OBSERVED
SOURCE
```

The source must point back to the trajectories and, when available, the repository evidence that supports the pattern.

## Step 4 — Confirm

A candidate becomes `CONFIRMED` only when evidence establishes that the rule is true and reusable.

Confirmation should come from one or more of:
- concrete code behavior;
- a passing test;
- verified repository state;
- independent repetition of the same rule in a new task;
- architecture evidence that establishes the boundary.

A repeated training sentence without external evidence is not confirmation.

## Step 5 — Promote

A confirmed grain becomes `PROMOTED` only when:
- it has been independently repeated, or
- it is architecture-critical.

Promotion means the knowledge becomes standing Agent OS knowledge, normally by incorporation into the appropriate durable surface such as `AGENTS.md` or `Documentation/ARCHITECTURE.md`.

Promotion must remain a separate decision from trajectory recording.

## First extraction from RUN-001–1000

Candidate:

**Evidence-first minimal repair**

Observed pattern:
- localize the exact task and repository state;
- identify the smallest valid action;
- preserve existing boundaries;
- verify with direct evidence;
- fail closed when evidence is insufficient;
- persist the resulting lesson/state.

STATUS: OBSERVED

SOURCE:
- `Documentation/LESSONS.md` (simulation-only trajectory log removed 2026-09-27; no CONFIRMED evidence)
- RUN-001 through RUN-1000
- Existing `AGENTS.md` operating rules
- Existing Living Cognitive Data Ocean contract

This candidate is intentionally **not** added to `REAL_GRAIN_SET_30.md` yet. Its repeated appearance in trajectories is evidence of recurrence, not independent proof of a new durable grain.

## Operating rule

The learning loop is:

```
Read
  ↓
Act
  ↓
Verify
  ↓
Extract
  ↓
Confirm
  ↓
Promote when earned
  ↓
Persist
```

Do not skip from `Trajectory → PROMOTED`.

## Next concrete implementation boundary

The next implementation should answer one question only:

> Given a set of trajectories, how does the Agent identify one candidate grain and attach the evidence needed for confirmation?

Until that retrieval/extraction need is demonstrated concretely, Markdown remains the canonical implementation and no parser, database, or automatic promotion engine is introduced.
