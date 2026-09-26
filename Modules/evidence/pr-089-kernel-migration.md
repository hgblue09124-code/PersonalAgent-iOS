# kernel-migration-boundary
ID
kernel-migration-boundary

PURPOSE
Move Kernel agent sources physically without redesigning behavior.

WHEN
Executing the canonical Kernel migration group.

RULE
Move the source group into Kernel/{Contracts,Errors,Ports}, update the SPM path, and block the next group until CI/build/tests are green and audited.

VERIFY
PR #89 defines the migration scope and explicit validation gate.

STATUS
CONFIRMED

SOURCE
PR #89 — migrate kernel agent sources to canonical Kernel tree