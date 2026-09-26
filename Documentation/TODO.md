# Issue #85 — RE-ARCH execution queue

> This queue is derived from the actual Issue #85 goal and the connected execution chain #87 → #88 → #89 → #90 → #91.
> PRs created after Issue #85 are execution/migration work for the same issue; they are not independent completion percentages.
> Do not invent equal-weight checkpoints or report a percentage unless repository evidence supports it.

## CURRENT STATE

- Issue #85: **OPEN — late-stage canonical migration, not complete**
- Active PR/workstream: **#91** — `rearch/cognition-policy-runtime`
- Current tested commit: `9b2f3b94ab57ddae7e46ef4cb2564cf2b485c17b`
- Latest verified workflow: **#718 / 36255114608 — VERIFIED GREEN**
- iOS arm64 build: **PASS**
- Repository integrity: **PASS**
- Swift package tests: **PASS**
- Full Gate: **PASS**
- PR Final — Filter: **PASS**
- The previous #712 Dependency direction blocker is **RESOLVED / VERIFIED**.

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
- [x] Fix the #712 **Dependency direction** test failure.
- [x] Re-run the full gate on the repaired/current HEAD.
- [x] Confirm Cognition/Policy legacy ownership is physically removed; recursive tree inspection found no `Sources/Core/Cognition`, `Sources/Core/Agency`, `Sources/Core/Policy`, `Cognition`, `Agency`, or `Policy` paths.
- [x] Confirm Runtime ownership is reflected in Package.swift and repository integrity checks.
- [x] Record verified PR #91 result: workflow #718 / 36255114608 GREEN.

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

1. **Audit actual remaining legacy paths from the current tree.**
2. **Execute the next confirmed migration group.**
3. **Re-verify PR #91 Full Gate after that migration.**
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