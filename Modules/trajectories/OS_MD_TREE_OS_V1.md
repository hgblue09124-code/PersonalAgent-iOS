# OS Markdown Tree OS V1

Status: DESIGN + SELF-PLAY READY

Purpose: turn the existing 1,000-run Markdown corpus into a self-playing cognitive
tree. The OS does not merely store more trajectories. It uses trajectories as
seed material to build reusable decision paths, failure traps, token shortcuts,
and progressively harder challenges.

This remains Markdown-native. No Swift runtime, parser, index, database, or model
fine-tuning is required.

## 1. Core idea

The OS treats every task as a routed search problem:

TASK
→ SNAPSHOT CURRENT STATE
→ CLASSIFY
→ ROUTE
→ SET CONTEXT BUDGET
→ LOAD MINIMAL HOUSE
→ SOLVE
→ VERIFY
→ FOLLOW
→ RESULT / DELTA
→ LEARN / PERSIST

The tree is the structural view. The executable cognitive shape is a graph:

NODE → SIGNAL → FOLLOW → NODE

A follow is a conditional transition, not a directory edge. It is created by an observable signal such as verification failure, missing evidence, a scope trap, a novel branch, or a cheaper verified route.

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

## 3. Tree becomes a cognitive graph

The Tree OS is not limited to parent/child traversal. Its nodes form a sparse cognitive graph whose edges are explicit FOLLOW transitions.

```text
                         ┌──→ FAILURE TRAP ──→ REPAIR SKILL ──┐
                         │                                     │
TASK → CLASSIFY → ROUTE → SKILL → ACT → VERIFY → RESULT ──────┤
             ↑       │                  │                      │
             │       │                  ├── missing evidence ──→ EVIDENCE
             │       │                  │
             │       └── shortcut ──────→ CHEAPER PATH         │
             │                                              ↓  │
             └────────────── FOLLOW ←──── DELTA ←──── LEARN ───┘
```

### 3.1 Node types

- **SKILL** — reusable action rule.
- **TRAP** — known failure twin and rejection rule.
- **EVIDENCE** — concrete proof needed to close a branch.
- **SHORTCUT** — cheaper path that preserves correctness, evidence, and scope.
- **DECISION** — routing rule selecting the next node.
- **CHALLENGE** — bounded self-play input used to test a route.
- **DELTA** — the smallest new fact produced by a completed run.

A node should stay small. The graph stores reusable transitions; trajectories remain the detailed historical record.

### 3.2 FOLLOW is the synapse

Every useful node may expose conditional follows:

```text
FOLLOW
  IF <signal>
  THEN <target node>
  WHY <transition reason>
  VERIFY <evidence that the transition was justified>
  COST <relative/estimated route cost>
  STATUS OBSERVED | CONFIRMED | PROMOTED
```

Examples:

```text
VERIFY
  PASS              → DONE
  FAIL              → FOLLOW: FAILURE-TRAP
  EVIDENCE-MISSING  → FOLLOW: EVIDENCE
  NOVEL             → FOLLOW: EXPLORE
  CHEAPER-VALID     → FOLLOW: SHORTCUT
```

The graph must not grow merely because two nodes are semantically related. A connection earns existence from an observable transition and its verification.

### 3.3 Routing is sparse and conditional

At execution time, do not load the whole graph. Start from the task and follow only edges whose signals match current state:

```text
L0 TASK
 ↓
L1 ROUTED SKILLS
 ↓ only when triggered
L2 TRAPS / SHORTCUTS
 ↓ only when evidence requires
L3 RELEVANT REPOSITORY EVIDENCE
 ↓ only when still unresolved
L4 NEIGHBORING GRAINS
 ↓ only when novel
L5 TEACHER
```

This keeps graph growth from becoming context growth.

### 3.4 Learning changes edge strength, not truth

Repeated successful transitions may make a route preferred, but frequency alone never upgrades a node or edge to CONFIRMED. The lifecycle remains:

```text
OBSERVED transition
  ↓
repeated / self-play tested
  ↓
candidate connection
  ↓
independent real-task evidence
  ↓
CONFIRMED
  ↓
independent repetition / architecture-critical
  ↓
PROMOTED
```

A cheaper route may become preferred only when:

```text
VALID
+ EVIDENCE PRESERVED
+ SCOPE PRESERVED
+ COST LOWER
```

The graph therefore learns routing efficiency without turning popularity into proof.

### 3.5 Neuron contract

A graph node is a **cognitive neuron** only when it has a bounded role, an activation condition, and a falsifiable exit condition. Markdown stores the contract; it does not pretend to be a neural runtime.

```text
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

Minimum semantic rule:

```text
TRIGGER      = when this neuron may activate
REQUIRED_STATE = what must already be true
ACTION       = what the neuron does
EXIT         = when it must stop firing
VERIFY       = what can justify the transition
```

A neuron without a bounded exit condition is a context sink. A neuron without provenance is not durable knowledge.

### 3.6 Synapse contract

A FOLLOW edge is a conditional synapse. Its strength controls routing preference, never truth.

```text
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

Semantics:

- **STRENGTH** = learned routing preference from verified experience; it is not confidence, truth, or authority.
- **FAILURE_COUNT** = observed failed traversals; it can suppress a route but cannot by itself prove a replacement.
- **LAST_EVIDENCE** = most recent evidence supporting the transition; stale evidence requires re-verification.
- **COST** = comparable route cost, measured when telemetry exists and explicitly estimated otherwise.
- **STATUS** = lifecycle state of the edge, independent of strength.

A route may be strengthened only after a successful traversal with preserved evidence and scope. A route may be weakened after a verified failure. Promotion still requires the existing independent-evidence lifecycle.

### 3.7 Activation, inhibition, and sparse attention

The graph behaves as a sparse cognitive network, not a fully connected neural net.

```text
TASK
 ↓ activate
TRIGGER-MATCHED NEURONS
 ↓ inhibit
TRAPS / STALE / SCOPE-MISMATCHED ROUTES
 ↓ select
LOWEST-COST VALID ROUTE
 ↓ expand only on unresolved evidence
NEIGHBORING NEURONS
```

Activation priority is:

```text
CURRENT STATE
→ TRIGGER MATCH
→ STATUS
→ EVIDENCE REQUIREMENT
→ ROUTE COST
→ STRENGTH
```

No single scalar may override the first four gates. In particular, a high-strength route is rejected when its evidence or scope is invalid.

**Inhibition rule:** a trap, stale edge, failed verification, or scope mismatch can block a route before more context is loaded.

**Sparse-context invariant:**

> Memory growth must not imply context growth.

The active set should contain only the smallest subgraph required to produce the next verified transition.

### 3.8 Learning, decay, and consolidation

Learning is a change in routing behavior, not an automatic change in truth.

```text
OBSERVATION
  ↓
SUCCESS / FAILURE SIGNAL
  ↓
EDGE UPDATE
  ↓
REPLAY / RECHALLENGE
  ↓
INDEPENDENT REAL-TASK EVIDENCE
  ↓
NODE/EDGE LIFECYCLE ADVANCE
```

Use bounded decay for routing preference:

```text
old / stale evidence
→ lower routing priority
→ re-verify before reuse
```

Decay affects **STRENGTH**, never **STATUS**. A CONFIRMED node does not become OBSERVED merely because it was unused; instead, stale evidence can require a fresh verification before activation.

Consolidation rule:

```text
TRAJECTORY = episodic experience
DELTA      = learning signal
GRAPH      = compressed reusable structure
HOUSE      = durable human-readable memory
```

Full trajectories remain cold evidence. The hot path should consume the compressed graph representation and fetch historical trajectories only when a verification or novelty trigger requires them.

### 3.9 Route selection and convergence

For a task with multiple valid routes, route selection is lexicographic rather than a single opaque score:

```text
1. VALIDITY
2. EVIDENCE PRESERVATION
3. SCOPE PRESERVATION
4. REUSE
5. LOWER COST
6. STRONGER ROUTING HISTORY
```

This prevents a cheap but unsafe route from defeating a more expensive verified route.

A route is **preferred**, not **true**, when it wins this comparison. The preferred route must be periodically rechallenged against its failure twin.

The graph is converging when repeated tasks show:

```text
same-or-better verified result
+ smaller active subgraph
+ fewer actions
+ lower measured/estimated cost
+ no increase in verification escapes
```

The target is therefore not maximum graph size. It is **minimum sufficient activation for a verified result**.
## 4. The house is the memory

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

## 5. Skill node

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

## 6. Self-play loop

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

## 7. Token economy is an objective, not permission to skip evidence

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

## 8. Failure twins

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

## 9. Teacher role

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

## 10. Tree growth rule

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

## 11. Current seeds from the 1,000-run corpus

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

## 12. First self-play curriculum

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

## 13. What success looks like

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

## 14. Guardrails

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

## 15. Current implementation boundary

This V1 is the cognitive architecture for the next phase of OS Markdown.

It intentionally does not claim that the repository already has an autonomous
self-playing runtime. The current implementation is a Markdown-native house
and curriculum that can be exercised by the agent/model loop.

The next real task should instantiate one graph-aware self-play cycle:

CHALLENGE → ROUTE → SOLVE → VERIFY → FOLLOW → ADVERSARY → JUDGE → COST COMPARE → COMPRESS → RECHALLENGE

The observable result should record which FOLLOW edges fired, which were rejected, and whether the route became cheaper without weakening evidence or scope.

The objective is not to make the Markdown file smarter by being longer.

The objective is to make the OS need **less context and fewer tokens to reach the
same verified result**.
