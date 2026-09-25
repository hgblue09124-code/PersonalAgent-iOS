# Task Handoff

<!-- TASK-CONTEXT: Issue #85 canonical migration bridge. Read AGENTS.md, ARCHITECTURE.md and AUDIT.md before continuing. -->

## Current Task
**RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**

## Completed
- Audit #13 mapping completed without moving production code.
- Audit #14 resolved remaining ownership gaps from actual responsibilities.
- Canonical ownership is frozen; no new top-level layer is required.
- No production/test behavior changed during mapping.

## Confirmed Findings
- Foundation → Kernel contracts/errors/ports.
- Shared provider boundary contracts → Kernel/Ports; provider/runtime implementation ownership → Providers or Runtime according to responsibility.
- HTTP transport/codecs/adapters → Providers/Remote.
- Local inference → Providers/Local; local model persistence → Storage/Models.
- Security/network protocols → Kernel/Ports; concrete persistence/network infrastructure → Storage/Configuration.
- Observability contracts → Kernel/Ports.
- ArchitectureManifest → Tests/Composition.
- Memory/Storage separated by semantic responsibility.
- Cognition/Agency/Policy redistributed into Runtime domains.
- ProductPersistenceContracts split by persistence responsibility; container remains Composition.

## Deferred Findings
- Exact type-level grouping inside split-heavy files happens during migration.
- Package.swift target graph/imports must be updated during moves.
- Physical iPhone 12 Pro Max validation remains final gate.

## Tests / Gates
- Mapping-only work made no production/test changes.
- Migration gate: build + full tests + dependency-direction audit after each group; physical iPhone validation at final gate.

## Exact Next Action
1. Migrate Kernel contracts/errors/ports first.
2. Move before rewrite; update imports/Package.swift only as required.
3. Build + full tests.
4. Audit dependency direction.
5. Record checkpoint in AUDIT.md.
6. Continue only if green.

<!-- DO NOT REDO: Do not restart provider feature work, UI redesign, llama.cpp optimization, or ownership discovery. Ownership is frozen. -->
