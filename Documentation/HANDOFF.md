# Task Handoff

<!-- TASK-CONTEXT: Issue #85 canonical migration bridge. Read AGENTS.md, ARCHITECTURE.md and AUDIT.md before continuing. -->

## Current Task

**RE-ARCH — Canonical PersonalAgent-iOS structure (Issue #85)**

## Current State

- Runtime ownership cleanup is complete and verified.
- Kernel coordination is reduced to the actually consumed module seam.
- Kernel contract imports/dependencies were minimized.
- PR #88 remains an intermediate cleanup point.
- **Audit #13 mapping is complete; no production/test files were moved during mapping.**

## Confirmed Mapping

- Kernel agent state machines/contracts/errors/ports → Kernel/{Contracts,Errors,Ports}.
- Events → Kernel/Events.
- Runtime files → Runtime/{Agent,Execution,Planning}, with semantic review for split-heavy files.
- Modules/Skills/Tools → Capabilities/{Modules,Skills,Tools}.
- Remote providers → Providers/Remote.
- Local provider + llama bridge → Providers/Local/LlamaCPP.
- Composition → Composition.
- App presentation → App/{Screens,Shared}.
- Tests → matching canonical domain mirrors.

## Unresolved Ownership — must resolve before moves

1. Sources/Providers/Contracts/*
2. Sources/Foundation/*
3. Sources/Security/SecretStore.swift and network contracts
4. Sources/Observability/AgentLogger.swift
5. Sources/Architecture/ArchitectureManifest.swift
6. Exact Memory/Storage semantic split
7. Exact Cognition/Agency/Policy contract split

## Exact Next Action

1. Inspect import/consumer evidence for the unresolved groups.
2. Freeze the file-level canonical map.
3. Update AUDIT.md and this handoff with final ownership decisions.
4. Only then create migration groups and move files.
5. After each move group: build + tests + architecture audit.

<!-- DO NOT REDO: Do not restart provider feature work. Do not redesign UI. Do not optimize llama.cpp. Do not invent new architecture folders. Do not move files before ownership is frozen. -->

## Handoff Rule

After each task, replace this section with: Completed; Confirmed findings; Deferred findings; Tests/gates; Exact next action; Do not redo.
