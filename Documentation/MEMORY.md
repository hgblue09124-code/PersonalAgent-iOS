# MEMORY — Agent Long-Term Repository Memory

> FAST PATH: Read **HOT MEMORY** first. Stop when it answers the task.
> Durable memory is cumulative. Current evidence outranks historical notes.

## HOT MEMORY

### Issue #85 — current truth
- Issue #85 is **one continuous canonical-repository migration**.
- PRs #87 → #91 are execution/migration work for Issue #85, not independent equal-weight milestones.
- Do **not** calculate progress as 1/8 or treat each PR as a separate issue completion percentage.
- The architecture/ownership-definition phase is largely complete; remaining work is primarily physical migration, dependency cleanup, verification, and final device acceptance.
- Current queue lives in `Documentation/TODO.md`; execute the first incomplete item only.

### Current CI truth
- Active PR: **#91**, branch `rearch/cognition-policy-runtime`.
- Current tested commit: `d89321d3798316ab0e6eb5f3899ea730fb923c2b`.
- Workflow **#712 / 36254250956** is **RED**.
- iOS arm64 build: PASS.
- Repository integrity: PASS.
- Swift package tests: FAIL in **Dependency direction**, exactly 1 issue.
- Full Gate: FAIL.
- Never call this HEAD green until a new completed Full Gate proves it.

### Completed architecture knowledge
- Ownership freeze is complete from Audit #14.
- Foundation → Kernel physical migration is complete at verified checkpoints; `Sources/Foundation` is absent on the current migration chain.
- Provider ownership migration and App boundary repairs have reached verified-green checkpoints in PR #91 history.
- Storage Models/Cache migration work is physically present in PR #91.
- Cognition/Agency/Policy have confirmed canonical Runtime destinations; PR #91 is completing the physical/runtime dependency migration.
- Events remains a separate migration scope; it is not automatically complete because Foundation is complete.

### Agent operating rule
- Markdown is a **soft memory protocol**: ordering/routing/STOP hints guide retrieval, not a rigid parser.
- Current/high-value information belongs near the top.
- Useful data may grow; optimize retrieval instead of deleting knowledge.
- Historical memory never overrides current repository/CI evidence.
- **agent on** means: read MD → inspect current repo/CI → execute the first TODO item → verify → record → handoff.

## MEMORY ROUTING
- `BASELINE.md` = current state.
- `Documentation/TODO.md` = executable queue.
- `Documentation/HANDOFF.md` = exact continuation action.
- `Documentation/WORK_LOG.md` = chronological execution evidence.
- `Documentation/AUDIT.md` = confirmed ownership/migration evidence.
- `Documentation/MEMORY.md` = durable lessons.
- `AGENTS.md` = operating contract.

## VERIFIED REPAIR LESSONS
- Never repair a red CI from the workflow title alone; inspect the failed job log and classify the exact failure first.
- A green PR verifies that PR/head only; it does not close Issue #85.
- Documentation-only commits still require a fresh Full Gate before the newer HEAD is called verified.
- A migration destination being documented is not proof that the physical source path is gone; verify the actual tree.

## HISTORY

### 2026-09-26 — Issue #85 progress-model correction
- Confirmed from Issue #85 and PR #87 → #91 that the PRs are a connected execution chain for one issue.
- Corrected the agent model: TODO must track **done vs remaining queue**, not fabricate equal-weight checkpoints.
- The architecture definition and ownership freeze are already substantially complete; the remaining queue is physical canonicalization + verification + final acceptance.

### 2026-09-26 — Fast-read Markdown system
- Markdown is a soft, memory-rich agent protocol.
- Current/high-value data is promoted near the top.
- STOP EARLY is preferred when the current section answers the task.
- Useful data generation is encouraged; retrieval efficiency comes from routing/indexing rather than suppressing knowledge.