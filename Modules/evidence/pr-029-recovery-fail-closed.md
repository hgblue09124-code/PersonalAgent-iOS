# recovery-fail-closed
ID
recovery-fail-closed

PURPOSE
Preserve uncertainty during runtime recovery.

WHEN
A target throws, times out, loses network, or recovery lacks definitive evidence.

RULE
Do not collapse UNKNOWN/UNAVAILABLE into FAILED or NOT_STARTED; enforce capability-aware recovery, stable WAL EventID replay, transaction-safe state reconciliation, and fail-closed approval.

VERIFY
PR #29 reports 274 unit/integration tests passing.

STATUS
CONFIRMED

SOURCE
PR #29 — runtime recovery and approval-gate repair