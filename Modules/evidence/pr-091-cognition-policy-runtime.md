# cognition-policy-runtime-ownership
ID
cognition-policy-runtime-ownership

PURPOSE
Place Cognition and Policy contracts under their canonical Runtime ownership.

WHEN
Contracts are physically located outside the runtime that owns their semantics.

RULE
Move Cognition contracts into Runtime ownership and Policy into Runtime/Verification; remove legacy targets only as part of the ownership migration.

VERIFY
PR #91 records the ownership migration and preserved behavior.

STATUS
CONFIRMED

SOURCE
PR #91 — Cognition and Policy into Runtime