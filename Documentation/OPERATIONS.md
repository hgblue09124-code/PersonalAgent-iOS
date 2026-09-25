# Safe Change Protocol

```text
Inspect → Confirm → Minimal change → Regression test → Full gate → Audit → Green
```

## Before

- Identify the last verified green baseline.
- Read the relevant architecture contract.
- Locate the real owner.
- Inspect callers, dependencies and tests.
- State the exact failure or architectural gap.

## During

- Keep scope narrow.
- Do not mix unrelated cleanup.
- Do not create a layer to hide a dependency.
- Preserve behavior unless explicitly changed.
- Keep vendor code behind adapters.

## After

Run focused tests, the full package suite, architecture/import checks, native build where applicable, physical validation where required, and a final diff audit.

## Merge

Never merge red work. If migration becomes unstable, return to the last verified green checkpoint and split the work into smaller slices.

## Agent report

Every implementation agent reports starting commit, changed files, responsibility moved, tests/results, remaining uncertainty and final commit. Compilation alone is not success.
