# MEMORY — Agent Long-Term Repository Memory

> FAST PATH: Read **HOT MEMORY** first. Stop when it answers the task.
> This is durable, cumulative memory—not a complete execution log.
> Useful data is welcome. Optimize retrieval, not data scarcity.

## HOT MEMORY
- Markdown is a **soft protocol**: headings, ordering, routing hints, and stop hints guide agents; they are not a rigid parser contract.
- Put high-value/current information near the top.
- Prefer **early stop** over exhaustive reading.
- Generate and preserve useful data freely; keep a compact hot section for retrieval.
- Historical memory never silently overrides current repository evidence.

## CURRENT REPOSITORY MEMORY
- Foundation migration is physically complete and verified on the current chain; old `Sources/Foundation` is absent.
- Next separate migration scope is Events → `Kernel/Events`.
- Issue #85 is the root canonical-architecture checkpoint.
- PR #91 is open on `rearch/cognition-policy-runtime`.
- Last verified PR HEAD: `a2f8861966a79a86471e070743e1a2abb54c1a9a`.
- Last verified Full Gate: #614 (`36233267763`) — green.
- Foundation and Events are separate migration scopes.

## MEMORY ROUTING
- `BASELINE.md` = now.
- `HANDOFF.md` = next action.
- `WORK_LOG.md` = execution history/evidence.
- `AUDIT.md` = architecture ownership/migration evidence.
- `MEMORY.md` = durable reusable knowledge/lessons.
- `AGENTS.md` = operating guidance.

## MEMORY WRITING
When useful knowledge is learned, append it to the most appropriate source. Do not avoid creating data merely to keep Markdown short. Put the newest/highest-value memory near the top and retain detailed history below.

Useful memory includes CI fingerprints/fixes, migration ownership, dependency-cycle discoveries, repository hazards, verified workflow behavior, agent mistakes/corrections, and deferred work.

## RETRIEVAL PRINCIPLE
**Index first → answer if possible → stop early → drill down only when needed.**

## HISTORY

### 2026-09-26 — Fast-read Markdown system
- Decision: Markdown is a soft, memory-rich agent protocol rather than a rigid schema.
- Decision: current/high-value information belongs near the top of each file.
- Decision: major Markdown sources expose a soft early-stop hint.
- Decision: data generation is encouraged; retrieval efficiency comes from indexing/routing, not deleting useful history.
