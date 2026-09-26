# MEMORY — Agent Long-Term Repository Memory

## HOT MEMORY
- Issue #85 is one continuous canonical migration; PRs #87 → #91 are execution steps, not independent completion percentages.
- **Current active PR:** #91, branch `rearch/cognition-policy-runtime`.
- Latest code checkpoint before documentation sync: `ecc520c0a1871e30cd64c380c3bd8c0a88ed865a`.
- Workflow #749 / `36260826735` was **VERIFIED GREEN** across Swift package tests, iOS arm64, repository integrity, Full Gate and PR Final.
- Memory target-boundary blocker is **RESOLVED**. Dedicated `PAStorageMemory` separates persistence from `PAMemory`.
- Confirmed Memory physical ownership:
  - `MemoryRuntime` → `Sources/Memory/Working`
  - `MemoryIndex` → `Sources/Memory/Retrieval`
  - `FileBackedMemoryStore` → `Storage/Memory`
  - `MemoryStorageRecord` + storage conformances → `Storage/Memory`
- Historical Markdown never overrides current repository/CI evidence.
- **agent on** means: read MD → inspect current repo/CI → execute first incomplete TODO item → verify → record → handoff.

## ROUTING
- `BASELINE.md` = current state.
- `Documentation/TODO.md` = executable queue.
- `Documentation/HANDOFF.md` = exact continuation.
- `Documentation/WORK_LOG.md` = execution evidence.
- `Documentation/AUDIT.md` = confirmed ownership/evidence.
