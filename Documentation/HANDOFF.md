# Task Handoff

<!-- TASK-CONTEXT: Issue #85 canonical migration bridge. Read AGENTS.md, ARCHITECTURE.md and AUDIT.md before continuing. -->

## Current Task
**RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**

## Completed
- Ownership freeze completed in Audit #14.
- Migration group #1 completed: Kernel agent source moved to canonical Kernel subdomains.
- PAKernel target now uses `Kernel` as its source path.
- Path-sensitive architecture tests updated and verified.

## Confirmed Findings
- 7 legacy Kernel agent files now have canonical homes.
- CI is green: Swift tests, repository integrity, and iOS arm64 build/unsigned IPA all pass.
- No behavior change was introduced.

## Deferred Findings
- Foundation remains a compatibility dependency and must be migrated carefully.
- Kernel Events remain outside Kernel until their migration group.

## Tests / Gates
- Swift package tests: PASS, 346 tests / 47 suites.
- Repository integrity greps: PASS.
- iOS arm64 build + unsigned IPA: PASS.

## Exact Next Action
1. Migrate `Sources/Foundation/*` into Kernel Contracts/Errors/Ports according to Audit #14.
2. Update all consumers/imports and Package.swift only as required.
3. Remove the legacy PAFoundation target only after dependency graph is green.
4. Run full tests + iOS build.
5. Audit dependency direction before continuing.

<!-- DO NOT REDO: Do not restart provider feature work, UI redesign, llama.cpp optimization, or ownership discovery. -->
