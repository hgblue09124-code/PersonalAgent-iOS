# OS Markdown Tree OS V1

Status: DESIGN + SELF-PLAY READY

Purpose: turn the existing 1,000-run Markdown corpus into a self-playing cognitive
tree. The OS does not merely store more trajectories. It uses trajectories as
seed material to build reusable decision paths, failure traps, token shortcuts,
and progressively harder challenges.

This remains Markdown-native. No Swift runtime, parser, index, database, or model
fine-tuning is required.

## 1. Core idea

The OS treats every task as a search problem:

TASK
→ READ current house
→ SELECT likely branch
→ SOLVE
→ VERIFY
→ ADVERSARIAL CHECK
→ COMPARE COST
→ COMPRESS
→ UPDATE HOUSE
→ GENERATE NEXT CHALLENGE

The strong model is a teacher/judge when needed. The durable asset is the OS
house: reusable skills, decision paths, traps, shortcuts, and challenge rules.

## 2. Tree shape

```text
TREE OS
├── ROOT: task
│
├── CLASSIFY
│   ├── current-state
│   ├── failure
│   ├── architecture
│   ├── verification
│   └── unknown
│
├── DECISION
│   ├── known skill
│   ├── nearby skill
│   └── explore
│
├── SOLVE
│   ├── shortest known path
│   ├── alternate path
│   └── teacher-assisted path
│
├── VERIFY
│   ├── invariant
│   ├── evidence
│   └── repository state
│
├── ADVERSARY
│   ├── hidden scope trap
│   ├── false-success trap
│   ├── overengineering trap
│   └── token-waste trap
│
├── COMPARE
│   ├── correctness
│   ├── evidence quality
│   ├── scope
│   └── token cost
│
└── HOUSE
    ├── Skills
    ├── Decision Maps
    ├── Failure Traps
    ├── Shortcuts
    └── Challenges
```

The tree is conceptual structure, not a requirement to create a directory or
runtime object for every node.

## 3. The house is the memory

A trajectory is temporary training material.

A house entry is reusable cognitive infrastructure.

A reusable entry should answer:

- WHEN does this branch apply?
- SIGNALS: what tells the OS it applies?
- DO: what is the shortest safe action?
- DON'T: what common trap should be avoided?
- VERIFY: what evidence closes the branch?
- COST: what makes this path cheap?
- STATUS: OBSERVED / CONFIRMED / PROMOTED
- SOURCE: where did the rule come from?

## 4. Skill node

Use this conceptual shape for future skill entries:

```text
SKILL
  WHEN
  SIGNALS
  ACTION
  DO NOT
  VERIFY
  TOKEN STRATEGY
  FAILURE TRAPS
  EVIDENCE
  STATUS
```

Example seed from the current corpus:

```text
SKILL: verification-preserving-minimal-repair

WHEN:
  a failing boundary has been localized

SIGNALS:
  concrete failure + matching code/test boundary

ACTION:
  repair only the smallest valid boundary

DO NOT:
  widen scope or weaken the verification mechanism

VERIFY:
  run evidence appropriate to the claimed invariant

TOKEN STRATEGY:
  start at the failure boundary; expand context only when evidence requires it

STATUS:
  OBSERVED until independently verified
```

This seed is derived from CL-003/CAND-001. It is not promoted by the corpus alone.

## 5. Self-play loop

The OS should challenge itself instead of endlessly appending easy examples.

### PASS A — Generator

Create a bounded challenge from an existing skill or decision branch.

Challenge families:

1. same task, less context;
2. same task, noisy context;
3. same task, misleading signal;
4. same invariant, multiple possible repairs;
5. same result, cheaper route;
6. previous failure with one trap removed;
7. previous success with a hidden scope trap.

### PASS B — Solver

The OS selects a path from the house.

Priority:

1. confirmed reusable skill;
2. observed skill with strong matching signals;
3. nearest decision branch;
4. exploration;
5. teacher assistance.

The solver should not reread the entire corpus when a bounded branch is enough.

### PASS C — Adversary

Generate the strongest plausible reason the chosen path is wrong.

Ask:

- Did the solver confuse execution with verification?
- Did it cross the task boundary?
- Did it assume remembered state?
- Did it weaken the evidence mechanism?
- Did it choose a longer route merely because it is familiar?
- Did it spend context on irrelevant files?
- Did it claim CONFIRMED without independent evidence?

### PASS D — Judge

Judge the result against the task invariant, not against confidence.

A passing solve needs:

- correct result;
- evidence appropriate to the claim;
- preserved boundary;
- no prohibited shortcut;
- acceptable token cost.

### PASS E — Compress

If two paths solve the same challenge safely:

```text
PATH A: correct + 140 units
PATH B: correct + 52 units

→ retain B as preferred shortcut
→ retain A only if it covers a distinct evidence case
```

The exact token count may be estimated when real token accounting is unavailable.
Never present an estimate as measured telemetry.

### PASS F — Rechallenge

Do not immediately trust the compressed shortcut.

Generate a new challenge that targets its weakest assumption.

If it survives, the branch becomes stronger. If it fails, create or refine a
failure trap.

## 6. Token economy is an objective, not permission to skip evidence

The OS optimizes:

```correctness
+ evidence
+ scope discipline
+ reuse
- unnecessary context
- unnecessary actions
- unnecessary repetition
```

Token saving must never mean:

- skipping required verification;
- hiding uncertainty;
- deleting tests;
- ignoring AGENTS.md;
- treating synthetic success as repository evidence.

The cheapest valid path is the target.

## 7. Failure twins

Every useful skill should eventually have a negative twin.

Example:

```SKILL
verification-preserving-minimal-repair
```

paired with:

```TRAP
green-by-bypass

SIGNAL:
  proposed change removes/weakens the mechanism that exposes failure

RESPONSE:
  reject path and restore the verification boundary
```

Other seed traps:

- BROAD-FIX-before-localization
- EXECUTION-EQUALS-VERIFICATION
- MEMORY-EQUALS-CURRENT-STATE
- TRAJECTORY-EQUALS-KNOWLEDGE
- REPETITION-EQUALS-PROOF
- CONTEXT-READ-EVERYTHING
- TOKEN-SAVING-BY-SKIPPING-EVIDENCE

These are challenge/judging patterns, not automatically confirmed repository
lessons.

## 8. Teacher role

The strong model should be used selectively.

```text
OS confident + evidence sufficient
    → act alone

OS has candidate but weak evidence
    → self-play + adversary

OS encounters novel branch
    → ask teacher for a bounded demonstration

teacher demonstrates
    → OS extracts observable pattern

OS creates challenge
    → teacher judges edge cases

repeated independent real-task success
    → candidate may advance lifecycle
```

Do not copy hidden chain-of-thought. Persist observable decisions, actions,
verification, failures, costs, and reusable rules.

## 9. Tree growth rule

Do not grow the tree because a file became large.

Grow it when a branch earns reuse.

```OBSERVED
  ↓
repeated pattern
  ↓
candidate skill
  ↓
self-play challenge
  ↓
adversarial failure check
  ↓
independent real-task evidence
  ↓
CONFIRMED
  ↓
independent repetition / architecture-critical
  ↓
PROMOTED
```

Synthetic self-play can strengthen or reject a candidate, but synthetic
evidence alone cannot turn it into a repository-confirmed lesson.

## 10. Current seeds from the 1,000-run corpus

The existing ten clusters become the first decision forest:

| Cluster | Tree role |
|---|---|
| CL-001 | current-state gate |
| CL-002 | classification branch |
| CL-003 | minimal-repair skill |
| CL-004 | scope/commit gate |
| CL-005 | verification gate |
| CL-006 | ownership/boundary gate |
| CL-007 | trajectory-to-grain extractor |
| CL-008 | lifecycle gate |
| CL-009 | persistence-cost gate |
| CL-010 | replay/evidence branch |

The corpus supplies seeds, not proof.

## 11. First self-play curriculum

Start with cheap challenges before creating more trajectory volume.

### T-001 — shortest safe repair
Given a localized failure, produce two valid paths and select the cheaper one.

### T-002 — false shortcut
Offer a faster path that weakens verification. Reject it.

### T-003 — context minimization
Solve with the smallest sufficient repository context.

### T-004 — noisy task
Inject unrelated files and test whether the OS keeps scope bounded.

### T-005 — stale-memory trap
Provide remembered state that conflicts with current repository state.

### T-006 — execution trap
Make the command succeed while the intended invariant remains false.

### T-007 — compression test
Replace a long successful path with a shorter reusable skill, then rechallenge it.

### T-008 — novel branch
Withhold a known skill and require the OS to identify the nearest safe branch.

### T-009 — adversarial replay
Replay a previous success with one hidden assumption changed.

### T-010 — teacher boundary
Ask the teacher only for the missing fact, not for a full solution.

## 12. What success looks like

The OS is improving when the same class of task requires:

```more reuse
less context
fewer actions
fewer repeated mistakes
same-or-better verification
```

A larger trajectory corpus is not itself success.

The stronger signal is:

```1000 trajectories
→ 10 clusters
→ reusable skills
→ negative twins
→ short decision paths
→ self-generated challenges
→ fewer tokens per valid solve
```

## 13. Guardrails

- One repository task remains one logical commit.
- Current repository state outranks remembered state.
- Synthetic runs are not repository evidence.
- CONFIRMED requires concrete independent evidence.
- PROMOTED follows existing lifecycle rules.
- Markdown remains the canonical human-readable surface.
- No parser/index/database is introduced until real usage demonstrates the need.
- The tree must not bypass Kernel, Runtime, Composition, Policy, or other
  executable boundaries.
- Token optimization may remove waste, never required evidence.

## 14. Current implementation boundary

This V1 is the cognitive architecture for the next phase of OS Markdown.

It intentionally does not claim that the repository already has an autonomous
self-playing runtime. The current implementation is a Markdown-native house
and curriculum that can be exercised by the agent/model loop.

The next real task should instantiate one self-play cycle:

CHALLENGE → SOLVE → ADVERSARY → JUDGE → COST COMPARE → COMPRESS → RECHALLENGE

and record the observable result.

The objective is not to make the Markdown file smarter by being longer.

The objective is to make the OS need **less context and fewer tokens to reach the
same verified result**.
