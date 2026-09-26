# execution-truth
ID
execution-truth

PURPOSE
Keep durable mutation evidence aligned with execution state.

WHEN
Recovery must determine whether a mutation happened across a crash boundary.

RULE
Persist mutation evidence and reconcile state journal status against the authoritative runtime; treat executor success and evidence as separate facts.

VERIFY
Failure-window tests cover prepared-before-mutation, mutation-before-journal, restart recovery, target-bound evidence, and contradiction handling.

STATUS
CONFIRMED

SOURCE
PR #31 — durability, capability, and execution-truth gaps