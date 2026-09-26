# ci-repair

ID
ci-repair

PURPOSE
Repair CI failures without changing unrelated behavior.

WHEN
A workflow fails during an Agent On task.

RULE
Inspect the exact failing workflow/job and changed scope first. Confirm the root cause from logs or repository state. Make the smallest repair. Re-run the affected gate and the full required gate before proceeding.

VERIFY
The exact commit has successful required workflow runs. Never infer CI success from Markdown notes.

STATUS
CONFIRMED

SOURCE
Agent On migration and CI repair history
