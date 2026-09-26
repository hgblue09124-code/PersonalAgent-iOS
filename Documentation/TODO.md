# Issue #85 — RE-ARCH execution TODO

> Rebuilt from the actual Issue #85 → PR #87 → #88 → #89 → #90 → #91 chain.
> PRs are stacked migration checkpoints; a green PR is not automatically completion of Issue #85.

## Completion model
- Issue completion % counts canonical architecture checkpoints only.
- PR #87 (architecture contract) and PR #88 (runtime atomicity repair) are supporting checkpoints, not separate migration layers.
- A migration checkpoint is DONE only when its physical repository state and required validation gate are verified.
- Final Issue #85 acceptance requires all migration checkpoints + documentation continuity + physical iPhone validation.

## Actual chain
- #87 — architecture contract: SUPPORTING — DONE.
- #88 — runtime state/event atomicity repair: SUPPORTING — DONE.
- #89 — Kernel agent sources: KERNEL GROUP — verified in prior checkpoint history.
- #90 — Foundation + Event contracts toward Kernel: KERNEL GROUP — verified in prior checkpoint history.
- #91 — Cognition + Policy into Runtime: RUNTIME GROUP — IN PROGRESS; latest verified CI is RED.

## Canonical TODO

### C1 — Kernel ownership
- [x] Kernel agent sources moved to canonical Kernel tree.
- [x] Foundation contracts/errors/ports and Event contracts moved toward canonical Kernel ownership.
- [x] Compatibility/Package/test ownership updated where verified.
- Gate: package graph + tests + repository integrity + iOS arm64 + Full Gate.

### C2 — Runtime ownership
- [ ] Cognition split across Runtime/Observation, Planning, Execution, Verification, Result.
- [ ] Policy contracts owned by Runtime/Verification.
- [ ] Legacy PACognition/PAPolicy targets removed without breaking dependency direction.
- [ ] Full Gate green after migration.
- Current blocker: PR #91 latest run #712 is RED.

### C3 — Memory ownership
- [ ] Working / Conversation / LongTerm / Retrieval have one canonical Memory home.
- [ ] Legacy Sources/Memory ownership is removed or proven as a deliberate compatibility boundary.
- [ ] Tests reflect canonical ownership.

### C4 — Storage ownership
- [ ] Models / Skills / Memory persistence / Configuration / Cache have one canonical Storage home.
- [ ] Storage model contracts have correct dependency direction.
- [ ] No accidental Storage → concrete Provider dependency remains.
- [ ] Full dependency-direction gate passes.

### C5 — Capabilities ownership
- [ ] Modules / Skills / Tools have one canonical Capabilities home.
- [ ] No duplicate Sources/Modules, Sources/Skills, Sources/Tools ownership remains unless explicitly justified.
- [ ] Runtime reaches capabilities through the canonical boundary.

### C6 — Providers ownership
- [ ] Remote and Local providers have one canonical adapter home.
- [ ] Vendor-specific implementation stays inside Providers.
- [ ] Kernel/Memory/Storage do not import concrete providers.
- [ ] Provider tests mirror canonical ownership.

### C7 — Composition + App + Tests
- [ ] Composition is the single wiring point.
- [ ] App remains presentation-only and does not directly wire concrete providers/storage/runtime.
- [ ] Tests mirror production ownership.
- [ ] Duplicate legacy composition ownership is removed or explicitly verified as a compatibility boundary.

### C8 — Final Issue #85 acceptance
- [ ] One canonical repository form.
- [ ] One home per concept/boundary.
- [ ] Dependency direction verified.
- [ ] Existing behavior preserved except required migration repairs.
- [ ] Swift tests green.
- [ ] Repository integrity green.
- [ ] iOS arm64 unsigned build green.
- [ ] Full Gate green.
- [ ] AUDIT / WORK_LOG / HANDOFF / BASELINE / MEMORY synchronized with evidence.
- [ ] Physical iPhone 12 Pro Max validation.
- [ ] Issue #85 acceptance complete.

## Current progress
- Canonical checkpoints: 8
- Completed: 1 / 8
- Current: C2 — Runtime ownership
- Remaining: C3–C8
- **Issue #85 completion: 12.5% by strict checkpoint accounting.**

> #89/#90 being historically verified does not make C2 complete. C2 is the entire Runtime ownership checkpoint, and PR #91 is currently failing its dependency-direction gate.

## Current CI evidence
- PR #91 tested commit: d89321d3798316ab0e6eb5f3899ea730fb923c2b
- Workflow #712: RED
- iOS arm64 build: PASS
- Repository integrity: PASS
- Swift package tests: FAIL — Dependency direction suite, 1 issue
- Full Gate/filter: FAIL
- Therefore C2 remains OPEN.

## Worker rule
Execute only the first incomplete checkpoint, then re-evaluate from repository evidence.

Workflow: inspect → confirm → minimal change → regression test → full gate → audit → record → handoff.

## Summary format
Issue #85: X/8 — Y% | Current: Cx | CI: GREEN/RED/CHƯA XÁC MINH | Blocker: ... | Next: ...
