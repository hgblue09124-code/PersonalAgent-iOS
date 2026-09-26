# Issue #85 — RE-ARCH execution queue

> This queue is derived from the actual Issue #85 goal and the connected execution chain #87 → #88 → #89 → #90 → #91.
> PRs created after Issue #85 are execution/migration work for the same issue; they are not independent completion percentages.
> Do not invent equal-weight checkpoints or report a percentage unless repository evidence supports it.

## CURRENT STATE

- Issue #85: **OPEN — late-stage canonical migration, not complete**
- Active PR/workstream: **#91** — `rearch/cognition-policy-runtime`
- Current tested commit: `d89321d3798316ab0e6eb5f3899ea730fb923c2b`
- Latest workflow: **#712 / 36254250956 — RED**
- iOS arm64 build: **PASS**
- Repository integrity: **PASS**
- Swift package tests: **FAIL** — Dependency direction suite, 1 issue
- Full Gate: **FAIL**
- Therefore the next worker must repair the confirmed CI blocker before opening the next migration group.

## WHAT IS ACTUALLY COMPLETED

### Issue foundation / architecture
- [x] Issue #85 canonical repository form and boundaries defined.
- [x] Architecture/ownership audit completed through Audit #14.
- [x] Ownership freeze completed from actual responsibility/import evidence.
- [x] Migration chain #87 → #91 established as one continuous Issue #85 workstream.

### Executed migration groups
- [x] PR #87 — architecture contract/supporting foundation.
- [x] PR #88 — runtime state/event atomicity repair/supporting work.
- [x] PR #89 — Kernel agent ownership migration.
- [x] PR #90 — Kernel/Foundation/Event/Runtime canonical migration work completed at its verified checkpoint.
- [x] Foundation → Kernel physical migration: `Sources/Foundation` removed; canonical Kernel ownership established and previously Full-Gate verified.
- [x] Provider ownership migration work in PR #91 has reached verified-green checkpoints.
- [x] App boundary and provider/import repairs in PR #91 reached verified-green checkpoints.
- [x] Storage model/cache migration work is physically present in the current PR.
- [x] Cognition/Policy canonical Runtime destinations are established and migration work is in progress.

## WHAT IS NOT COMPLETE

### P1 — Finish current PR #91 / Runtime + remaining migration mechanics
- [ ] Fix the current **Dependency direction** test failure in workflow #712.
- [ ] Re-run the full gate on the repaired HEAD.
- [ ] Confirm Cognition/Policy legacy ownership is physically removed, not merely mapped.
- [ ] Confirm Runtime ownership is reflected consistently in Package.swift, tests, and repository integrity.
- [ ] Record the verified PR #91 result.

### P2 — Remaining canonical migration groups
These are the remaining queue only after the current PR is green. They are not separate Issue #85 percentages.

- [ ] Events → `Kernel/Events` complete and verified.
- [ ] Memory → canonical `Memory/{Working,Conversation,LongTerm,Retrieval}` complete; storage persistence separated.
- [ ] Storage → canonical `Storage/{Models,Skills,Memory,Configuration,Cache}` complete and dependency direction verified.
- [ ] Capabilities → canonical `Capabilities/{Modules,Skills,Tools}` complete.
- [ ] Providers → canonical Remote/Local ownership fully reconciled; retain only deliberate contract targets/boundaries.
- [ ] Composition → single wiring boundary verified.
- [ ] App → presentation-only boundary verified.
- [ ] Tests → production ownership mirrored by test topology.
- [ ] Remove/prove every remaining legacy duplicate ownership path.

### P3 — Final Issue #85 acceptance
- [ ] One canonical repository form verified from the actual tree.
- [ ] One home per concept/boundary verified.
- [ ] Dependency direction fully green.
- [ ] Existing behavior preserved except migration repairs.
- [ ] Swift package tests green.
- [ ] Repository integrity green.
- [ ] iOS arm64 unsigned build green.
- [ ] Full Gate green on the final Issue #85 state.
- [ ] AUDIT / WORK_LOG / HANDOFF / BASELINE / MEMORY synchronized to the final verified state.
- [ ] Physical iPhone 12 Pro Max validation.
- [ ] Issue #85 closed only after all acceptance evidence exists.

## WORK QUEUE ORDER

1. **Repair workflow #712** — confirmed red Dependency direction test.
2. **Re-verify PR #91 Full Gate.**
3. **Audit actual remaining legacy paths from the current tree.**
4. **Execute only the next confirmed migration group.**
5. **Final canonical-tree/dependency audit.**
6. **Physical iPhone validation.**
7. **Issue #85 final acceptance/close.**

## AGENT RULE

When an agent starts with **agent on**:
- Read this queue plus BASELINE/MEMORY.
- Trust current repository/CI evidence over historical Markdown.
- Execute the **first incomplete item only**.
- After each completed repair/migration: update WORK_LOG + HANDOFF + relevant memory.
- Do not reopen completed groups unless current evidence proves regression.
- Do not calculate Issue #85 progress as `1/8`; the PR chain is one continuous execution of the Issue.

## STOP CONDITION

If the current CI failure is ambiguous, inspect the failing test/log and stop before guessing.