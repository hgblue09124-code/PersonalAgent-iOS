# ci-check-consolidation
ID
ci-check-consolidation

PURPOSE
Reduce duplicate CI notifications without weakening verification.

WHEN
Multiple CI jobs perform the same logical check.

RULE
Consolidate duplicate checks only when every existing test and integrity assertion remains unchanged; retain the Apple native lane when it owns distinct Xcode/IPA evidence.

VERIFY
PR #93 explicitly preserves all test/integrity assertions and keeps Apple Native Build separate.

STATUS
CONFIRMED

SOURCE
PR #93 — consolidate duplicate CI check notifications