# evidence-resolution-contract
ID
evidence-resolution-contract

PURPOSE
Keep ambiguous execution outcomes from being silently treated as success or failure.

WHEN
Execution completion conflicts with unavailable or unresolved evidence.

RULE
Use explicit evidence-resolution and unresolved dispositions; preserve stable EventID binding and idempotent event append semantics.

VERIFY
Recovery semantics are covered by the M7 repair PR and its acceptance contract.

STATUS
CONFIRMED

SOURCE
PR #26 — M7.0 recovery semantics repair