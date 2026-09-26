# Personal Agent OS Markdown

Status: Product foundation.

Personal Agent OS Markdown is a Markdown-native Personal OS for an agent.

Markdown is not treated as generated documentation. It is a persistent, human-readable and agent-readable cognitive state layer that can be versioned, reviewed, diffed, and carried across agent sessions.

## Product model

```
Human Intent
    ↓
Markdown State
    ↓
Agent
    ↓
Action
    ↓
Evidence
    ↓
Markdown State
    ↓
Learn
    ↺
```

The core loop is:

**Read → Act → Verify → Learn → Persist**

## Cognitive planes

| Markdown surface | Role |
| --- | --- |
| `AGENTS.md` | identity, operating rules, hard constraints |
| `Documentation/ARCHITECTURE.md` | world model and ownership |
| `Documentation/LESSONS.md` | durable evidence-backed learning |
| `Documentation/AUDIT.md` | verified claims and findings |
| `Documentation/HANDOFF.md` | current working state and exact next action |
| `Documentation/WORK_LOG.md` | execution history and evidence |

These files are complementary. They must not become duplicate session diaries.

## State lifecycle

A fact or lesson progresses only when evidence supports it:

```
OBSERVED
   ↓ verify
CONFIRMED
   ↓ repeated or architecture-critical
PROMOTED
```

Promotion means the knowledge has become a standing rule in `AGENTS.md` or `Documentation/ARCHITECTURE.md`.

## Product invariants

1. Markdown remains readable and useful to humans without an Agent.
2. Agent actions must be grounded in current repository state and evidence.
3. No lesson is promoted from speculation.
4. Working state is explicit; the next action must be recoverable from Markdown.
5. Markdown is versioned with the same discipline as source code.
6. One logical task remains one logical commit after squash merge.
7. The Markdown layer must not bypass runtime ownership or architecture boundaries.

## Evolution path

The product can evolve from Markdown files into an indexed cognitive layer without changing the persistence contract:

```
Markdown
   ↓
Parser / Index
   ↓
Memory Model
   ↓
Retrieval
   ↓
Agent Loop
   ↓
Evidence
   ↓
Markdown
```

The first implementation deliberately keeps Markdown as the canonical persistence surface.