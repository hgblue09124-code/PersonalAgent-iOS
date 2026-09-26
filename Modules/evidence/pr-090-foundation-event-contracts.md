# foundation-event-contract-migration
ID
foundation-event-contract-migration

PURPOSE
Consolidate Foundation, event, and module execution port contracts under Kernel ownership.

WHEN
A contract belongs to the lowest stable architectural layer.

RULE
Move contracts toward Kernel while retaining compatibility bridges when required; do not redesign product behavior during a physical migration.

VERIFY
PR #90 explicitly scopes the migration and compatibility bridges with no product behavior redesign.

STATUS
CONFIRMED

SOURCE
PR #90 — Foundation and event contracts toward Kernel