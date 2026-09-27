# OS Markdown Tree OS V1

Status: DESIGN + SELF-PLAY READY

Purpose: turn trajectory evidence into a sparse, reusable cognitive graph while
keeping Markdown as the canonical human-readable memory surface.

This is a Markdown contract, not a Swift runtime. No parser, index, database, or
model fine-tuning is required.

## 1. Core loop

```
TASK
→ SNAPSHOT
→ CLASSIFY
→ ROUTE
→ LOAD MINIMAL HOUSE
→ SOLVE
→ VERIFY
→ FOLLOW
→ RESULT / DELTA
→ LEARN / PERSIST
```

Structural view: **tree**. Operational view: sparse graph.

```
NODE → SIGNAL → FOLLOW → NODE
```

A FOLLOW edge exists only when an observable transition and its verification justify it.

## 2. Cognitive structure

```
TASK
 └→ CLASSIFY
     └→ ROUTE
         └→ SKILL → ACT → VERIFY
                    ├→ DONE
                    ├→ TRAP / REPAIR
                    ├→ EVIDENCE
                    ├→ SHORTCUT
                    └→ EXPLORE
```

Node types:

- **SKILL** — reusable action rule.
- **TRAP** — failure twin / rejection rule.
- **EVIDENCE** — proof needed to close a branch.
- **SHORTCUT** — cheaper verified route.
- **DECISION** — routing rule.
- **CHALLENGE** — bounded self-play input.
- **DELTA** — smallest new fact from a run.

The tree is conceptual; nodes do not imply directories or runtime objects.

## 3. Neuron / synapse contract

A neuron is an existing OS skill, trap, decision, evidence rule, shortcut, or
challenge with explicit activation and exit conditions. This is an **upgrade to
the existing OS**, not a replacement architecture.

```
NEURON
  ID
  TYPE
  TRIGGER
  REQUIRED_STATE
  ACTION
  EXIT_CONDITION
  VERIFY
  FAILURE_TWIN
  PROVENANCE
  STATUS OBSERVED | CONFIRMED | PROMOTED
```

A neuron without a bounded exit is a context sink. Without provenance it is not
durable knowledge.

A FOLLOW edge is a synapse:

```
SYNAPSE
  SOURCE
  SIGNAL
  TARGET
  WHY
  VERIFY
  COST
  STRENGTH
  FAILURE_COUNT
  LAST_EVIDENCE
  STATUS OBSERVED | CONFIRMED | PROMOTED
```

**STRENGTH is routing preference, never truth.** Failure count may suppress a
route but cannot prove a replacement. Stale evidence requires re-verification.

## 4. Sparse routing

Never load the whole graph.

```
TASK
 ↓
TRIGGER-MATCHED NEURONS
 ↓ inhibit
TRAPS / STALE / SCOPE-MISMATCHED ROUTES
 ↓ select
LOWEST-COST VALID ROUTE
 ↓ expand only when evidence requires
NEIGHBORING GRAINS
 ↓ only when novel
TEACHER
```

Priority:

```
CURRENT STATE
→ TRIGGER
→ STATUS
→ EVIDENCE REQUIREMENT
→ COST
→ ROUTING HISTORY
```

No cost or strength value may override validity, evidence, or scope.

**Invariant:** memory growth must not imply context growth.

## 5. Learning and lifecycle

```
OBSERVATION
→ SUCCESS / FAILURE SIGNAL
→ EDGE UPDATE
→ REPLAY / RECHALLENGE
→ INDEPENDENT REAL-TASK EVIDENCE
→ LIFECYCLE ADVANCE
```

```
TRAJECTORY = episodic evidence
DELTA      = learning signal
GRAPH      = compressed reusable structure
HOUSE      = durable human-readable memory
```

Routing preference may decay when evidence becomes stale. STATUS does not decay
automatically.

Lifecycle remains:

```
OBSERVED → CONFIRMED → PROMOTED
```

- Synthetic self-play can reject or refine a candidate.
- Repetition is a signal, not proof.
- CONFIRMED requires concrete independent evidence.
- PROMOTED requires independent repetition or architecture-critical justification.

## 6. Route selection

Compare valid routes lexicographically:

1. validity;
2. evidence preservation;
3. scope preservation;
4. reuse;
5. lower cost;
6. routing history.

A cheaper route becomes preferred only when:

```
VALID
+ EVIDENCE PRESERVED
+ SCOPE PRESERVED
+ COST LOWER
```

Convergence means the same-or-better verified result with less active context,
fewer actions, and no increase in verification escapes.

Target: **minimum sufficient activation for a verified result**.

## 7. Traversal safety

Self-play must not loop indefinitely.

```
PATH_STATE
  TASK_ID
  VISITED_NODES
  FIRED_EDGES
  STEP_BUDGET
  EXPANSION_COUNT
  REENTRY_GUARD
```

Rules:

1. visited nodes do not re-fire without a new verification signal;
2. repeated edges without new evidence are inhibited;
3. step budget bounds one self-play attempt;
4. expansion count bounds context/traversal growth;
5. retrying a cycle requires changed challenge or new evidence.

A cyclic route such as `A → B → A → B` must terminate as
`CYCLE_INHIBITED` or `BUDGET_EXHAUSTED`, never as a verified result.

This guard is routing safety, not truth.

## 8. House entry

Reusable memory should answer:

```
WHEN / SIGNALS / ACTION / DO NOT / VERIFY / COST / STATUS / SOURCE
```

Seed:

```
SKILL: verification-preserving-minimal-repair

WHEN:
  failure boundary is localized

ACTION:
  repair the smallest valid boundary

DO NOT:
  widen scope or weaken verification

VERIFY:
  evidence appropriate to the claimed invariant

STATUS:
  OBSERVED until independently verified
```

The seed is not promoted by corpus volume alone.

## 9. Self-play

Each bounded cycle is:

```
CHALLENGE
→ ROUTE
→ SOLVE
→ VERIFY
→ FOLLOW
→ ADVERSARY
→ JUDGE
→ COST COMPARE
→ COMPRESS
→ RECHALLENGE
```

Challenge families:

- same task with less/noisy context;
- misleading signal or hidden scope trap;
- multiple valid repairs;
- same result through a cheaper route;
- stale-memory or execution-vs-verification trap;
- previous success with one assumption changed;
- novel branch requiring bounded teacher help.

Judge against the invariant:

- correct result;
- required evidence present;
- boundary preserved;
- no prohibited shortcut;
- acceptable cost.

If two safe routes solve the same task, prefer the cheaper one and rechallenge it
before treating the shortcut as durable.

Teacher use is selective: unknown branch → bounded demonstration → observable
pattern → challenge → independent real-task evidence.

Never persist hidden chain-of-thought; persist observable decisions, actions,
verification, failures, costs, and reusable rules.

## 10. Token economy

```
correctness
+ evidence
+ scope discipline
+ reuse
- unnecessary context
- unnecessary actions
- unnecessary repetition
```

Token optimization never permits:

- skipped required verification;
- hidden uncertainty;
- deleted tests;
- ignored AGENTS.md;
- synthetic success presented as repository evidence.

The cheapest **valid** path is the target.

## 11. Failure twins

Core traps:

- GREEN-BY-BYPASS
- BROAD-FIX-before-localization
- EXECUTION-EQUALS-VERIFICATION
- MEMORY-EQUALS-CURRENT-STATE
- TRAJECTORY-EQUALS-KNOWLEDGE
- REPETITION-EQUALS-PROOF
- CONTEXT-READ-EVERYTHING
- TOKEN-SAVING-BY-SKIPPING-EVIDENCE

These are judging/challenge patterns, not automatically confirmed lessons.

## 12. Curriculum seeds

The first decision forest maps the existing corpus:

| Cluster | Role |
|---|---|
| CL-001 | current-state gate |
| CL-002 | classification |
| CL-003 | minimal repair |
| CL-004 | scope / commit |
| CL-005 | verification |
| CL-006 | ownership / boundary |
| CL-007 | trajectory → grain |
| CL-008 | lifecycle |
| CL-009 | persistence cost |
| CL-010 | replay / evidence |

First challenges:

```
T-001 shortest safe repair
T-002 false shortcut
T-003 minimum context
T-004 noisy scope
T-005 stale memory
T-006 execution trap
T-007 compression + rechallenge
T-008 novel branch
T-009 adversarial replay
T-010 teacher boundary
```

The corpus supplies seeds, not proof.

## 13. Guardrails

- One repository task = one logical commit.
- Current repository state outranks remembered state.
- Synthetic runs are not repository evidence.
- CONFIRMED requires independent concrete evidence.
- Markdown remains canonical human-readable persistence.
- No parser/index/database until real usage demonstrates a retrieval need.
- The cognitive graph must not bypass Kernel, Runtime, Composition, Policy, or
  other executable ownership boundaries.
- Token optimization may remove waste, never required evidence.

## 14. Current implementation boundary

V1 is the cognitive architecture for the next OS Markdown phase. The repository
does **not** yet claim an autonomous self-playing runtime.

Current implementation: Markdown-native house + curriculum exercised by the
agent/model loop.

Synthetic cycle test already exposed the need for explicit traversal bounds;
the cycle guard above records that repair as **OBSERVED** until an independent
real repository task exercises it.

Next real task:

```
CHALLENGE → ROUTE → SOLVE → VERIFY → FOLLOW
→ ADVERSARY → JUDGE → COST COMPARE → COMPRESS → RECHALLENGE
```

Record only observable outcomes: fired/rejected FOLLOW edges, verification,
scope preservation, and route cost.

**Success is not a larger Markdown file. Success is the same verified result with
less active context and fewer unnecessary actions.**
