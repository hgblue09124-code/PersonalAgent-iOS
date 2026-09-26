# Issue #85 — RE-ARCH execution queue

## CURRENT STATE
- Issue #85: **OPEN — late-stage canonical migration, not complete**
- Active PR/workstream: **#91** — `rearch/cognition-policy-runtime`
- Current tested commit: `ecc520c0a1871e30cd64c380c3bd8c0a88ed865a`
- Latest verified workflow: **#749 / 36260826735 — VERIFIED GREEN**
- iOS arm64 / repository integrity / Swift package tests / Full Gate / PR Final: **PASS**
- #712 Dependency direction blocker: **RESOLVED / VERIFIED**

## WHAT IS ACTUALLY COMPLETED
- [x] Architecture contract and ownership freeze.
- [x] PR #87 → #91 connected execution chain.
- [x] Kernel/Foundation/Events physical migrations verified.
- [x] Provider/App/Runtime migration checkpoints verified.
- [x] Memory target-boundary blocker resolved by introducing the dedicated `PAStorageMemory` target.
- [x] Memory physical split present: Working/Retrieval semantics and Storage/Memory persistence boundary.
- [x] Memory storage conformance isolated at the storage boundary.
- [x] Current PR #91 Full Gate green at workflow #749.

## WHAT IS NOT COMPLETE
- [ ] Storage → canonical `Storage/{Models,Skills,Memory,Configuration,Cache}` complete and dependency direction verified.
- [ ] Capabilities → canonical `Capabilities/{Modules,Skills,Tools}` complete.
- [ ] Providers → canonical Remote/Local ownership fully reconciled.
- [ ] Composition → single wiring boundary verified.
- [ ] App → presentation-only boundary verified.
- [ ] Tests → production ownership mirrored by test topology.
- [ ] Remove/prove every remaining legacy duplicate ownership path.
- [ ] Final canonical-tree + dependency-direction audit.
- [ ] Physical iPhone 12 Pro Max validation.
- [ ] Final Issue #85 acceptance and close.

## WORK QUEUE ORDER
1. **Re-verify current PR #91 Full Gate after the latest verified Memory fixes.**
2. **Execute only the next confirmed migration group: Storage/remaining boundary cleanup.**
3. Final canonical-tree/dependency audit.
4. Physical iPhone validation.
5. Issue #85 final acceptance/close.

## AGENT RULE
When `agent on`: read BASELINE/MEMORY/TODO, inspect current PR/CI, execute the first incomplete item, verify, record, handoff. Never infer CI state from history.

## STOP CONDITION
If a failure is ambiguous, inspect the failing job/log and stop before guessing.
