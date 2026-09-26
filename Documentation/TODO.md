# Issue #85 — RE-ARCH Canonical PersonalAgent-iOS TODO

> Progress is measured by completed acceptance checkpoints, not by changed-file count.
> Every checkpoint requires repository evidence. Do not mark DONE from design intent alone.

## Progress
- Total checkpoints: 10
- Completed: 2 / 10
- Current completion: 20%
- Current workstream: PR #91 / Memory–Storage canonicalization
- Rule: a checkpoint becomes DONE only after code + tests/CI + required documentation evidence are verified.

## TODO by Issue #85

### Phase 1 — Canonical foundation
- [x] T01 — Foundation → Kernel
  Move/verify Foundation contracts, errors and ports under canonical Kernel ownership.
  Gate: package graph + tests + repository integrity + iOS arm64 + Full Gate.
- [x] T02 — Events → Kernel/Events
  Move/verify Events under canonical Kernel ownership and remove legacy ownership.
  Gate: package graph + tests + repository integrity + iOS arm64 + Full Gate.

### Phase 2 — Memory / Storage
- [ ] T03 — Memory semantic ownership
  Verify/migrate Working, Conversation, LongTerm, Retrieval to Memory/*.
- [ ] T04 — Storage ownership
  Verify/migrate Models, Memory persistence, Configuration, Cache and related storage boundaries to Storage/*.
- [ ] T05 — Memory/Storage dependency gate
  Remove stale ownership/targets/imports; verify dependency direction and regression coverage.
  Gate: Swift tests + repository integrity + iOS arm64 + Full Gate.

### Phase 3 — Runtime / Capabilities / Providers
- [ ] T06 — Runtime canonical ownership
  Verify Agent, Execution, Planning, Observation, Verification, Result have one canonical home and one execution path.
- [ ] T07 — Capabilities + Providers canonical ownership
  Verify Modules, Skills, Tools and Remote/Local provider adapters have one canonical home and correct dependency direction.

### Phase 4 — Composition / App / Tests
- [ ] T08 — Composition wiring
  Verify construction/wiring is centralized in Composition and no duplicate dependency wiring remains.
- [ ] T09 — App + Tests topology
  Verify App presentation boundaries and Tests mirror production ownership without direct vendor/runtime/storage leakage.

### Phase 5 — Final acceptance
- [ ] T10 — Integrated Issue #85 acceptance
  Verify one canonical repository form, no duplicate ownership, dependency direction, behavior preservation, green Build/Tests/Full Gate, required Markdown continuity, and physical iPhone 12 Pro Max validation.

## Execution contract
Every unchecked item follows:
inspect → confirm → minimal change → regression test → full gate → audit → record → handoff

### Completion accounting
- Checkpoint DONE only with evidence.
- Failed CI does not count as completion.
- A green intermediate PR counts only for the checkpoint it actually verifies.
- If a checkpoint is split into multiple PRs, count it once when the whole checkpoint is verified.
- At every final summary report: Completed X/10; Progress Y%; Current Txx; Blocked/Deferred; Evidence.

## Stop rules
- Do not create a new architectural layer just to make a TODO item pass.
- Do not redesign product UI, optimize llama.cpp, or add providers/models under this issue.
- Do not mark future architecture as confirmed before repository evidence exists.
- If ownership is ambiguous, stop and record NOT CONFIRMED.