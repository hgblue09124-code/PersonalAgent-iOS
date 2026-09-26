# contaminated-branch

ID
contaminated-branch

PURPOSE
Keep focused migration work isolated from unrelated migration history.

WHEN
Preparing a focused migration PR against main.

RULE
Create the working branch directly from the current main commit and stage only the confirmed task scope.

VERIFY
Compare the PR head against main. Changed files and commit history must represent one logical task.

STATUS
CONFIRMED

SOURCE
L-002 / PR #95–#98 migration history
