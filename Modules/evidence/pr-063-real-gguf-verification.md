# real-gguf-verification
ID
real-gguf-verification

PURPOSE
Prove the actual local GGUF execution call graph rather than assuming model load implies execution.

WHEN
Verifying a real local agent path.

RULE
Trace storage → runtime coordination → native engine → provider adapter → output validation and test failure geometries independently.

VERIFY
PR #63 reports automated verification of failure geometries F1–F7.

STATUS
CONFIRMED

SOURCE
PR #63 — M9.1 Real GGUF Execution Verification