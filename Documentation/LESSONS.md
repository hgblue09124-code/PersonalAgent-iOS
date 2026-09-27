# LESSONS.md

Durable, evidence-backed lessons for Agent On work.

## Rules

- Read this file before non-trivial repository work.
- Record only durable lessons; do not use it as a session diary.
- A lesson starts as `OBSERVED` and becomes `CONFIRMED` only after code, test, or CI evidence establishes the cause.
- `PROMOTED` means the lesson has been repeated independently or is architecture-critical and has been incorporated into a standing rule in `AGENTS.md` or `Documentation/ARCHITECTURE.md`.
- Every confirmed lesson must include a concrete verification path and source evidence.
- Do not duplicate `WORK_LOG.md`; extract the reusable rule instead.
- Do not create a separate memory commit. Lesson updates belong to the same logical task commit.

## Lesson Schema

```md
## L-NNN — Title

WHEN
- Trigger condition.

OBSERVED
- Concrete symptom.

ROOT CAUSE
- Evidence-backed cause.

RULE
- Reusable instruction for future work.

VERIFY
- Exact test, check, or CI evidence.

STATUS: OBSERVED | CONFIRMED | PROMOTED
SOURCE
- Commit, workflow run, or other concrete repository evidence.
```

## L-001 — Removing a Swift package product requires Xcode project cleanup

WHEN
- A Swift package product/target is removed from `Package.swift`.

OBSERVED
- SPM-side changes can be correct while the Apple build still reports `Missing package product`.

ROOT CAUSE
- `PersonalAgent.xcodeproj/project.pbxproj` can retain stale `XCSwiftPackageProductDependency`, package dependency, or framework build-file entries.

RULE
- After removing a package product, inspect both `Package.swift` and `PersonalAgent.xcodeproj/project.pbxproj` before declaring the migration complete.

VERIFY
- Apple Native Build must pass after the stale Xcode references are removed.

STATUS: CONFIRMED
SOURCE
- PR #98 Apple Native Build failure and repair on 2026-09-27.

## L-002 — Do not build a migration PR from a contaminated integration branch

WHEN
- A physical migration is being prepared as a focused PR against `main`.

OBSERVED
- A PR can contain unrelated migration history when its branch was reused from an older integration branch.

ROOT CAUSE
- Branch `rearch/kernel-migration-2` carried unrelated prior migration commits into the Composition PR lineage.

RULE
- For a focused migration, create the working branch directly from the current `main` commit and stage only the confirmed task scope.

VERIFY
- Compare the PR head against `main`; the changed files and commit history must match the single logical task.

STATUS: CONFIRMED
SOURCE
- PR #96 contamination and clean rebuild for PR #97 on 2026-09-27.
