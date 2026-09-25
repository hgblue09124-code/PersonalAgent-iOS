# Architecture Audit

<!-- TASK-CONTEXT: This file records evidence from architecture audits. It is not a wish list. Every finding must state whether it is confirmed, not confirmed, or deferred. -->

## Finding Format

- **Confirmed** — evidence exists in the repository.
- **Not Confirmed** — inspection did not establish the concern.
- **Deferred** — real concern exists but is intentionally postponed.

<!-- INVARIANT: Do not convert an architectural smell into a confirmed bug without evidence. Behavior bugs require a reproducible failure and regression coverage. -->

## Audit Log

### Audit #12 — Current recorded checkpoint

- Confirmed: unsupported `stateUpdate(.proposed)` must fail closed without mutation.
- Confirmed: runtime state/event atomicity fixes are covered by regression tests.
- Confirmed: Kernel contract imports and direct dependencies were minimized.
- Deferred: full canonical physical-tree migration from Issue #85.

<!-- HANDOFF: The next audit must start from the repository state on the active migration branch. Do not repeat already-verified behavioral fixes unless a migration touches them. -->

## Next Audit

### Canonical Tree Audit

Inspect the complete current tree and map every production/test component to the Issue #85 canonical structure.

Required output:
`Current path -> canonical path -> ownership evidence -> action -> confidence`

Do not move files during the mapping-only audit.


### Audit #13 — Canonical Tree Mapping (mapping-only)

<!-- TASK-CONTEXT: Issue #85 mapping audit. Repository state inspected at baseline/architecture-m8. No production/test files were moved or rewritten in this audit. -->
<!-- DECISION: Mapping distinguishes direct placement, semantic split, and unresolved canonical gaps. Do not invent folders to make every legacy target fit. -->
<!-- INVARIANT: Every current component must have exactly one eventual canonical owner; a file spanning multiple domains must be split by semantics before migration. -->

**Result:** Mapping completed for the current production tree, App tree, vendor boundary, and test tree. Physical migration is **not started**.

#### Direct / high-confidence mappings

- Sources/Core/Agent/GoalMachine.swift → Kernel/Contracts/GoalMachine.swift
- Sources/Core/Agent/LifecycleMachine.swift → Kernel/Contracts/LifecycleMachine.swift
- Sources/Core/Agent/KernelContracts.swift → Kernel/Contracts/KernelContracts.swift
- Sources/Core/Agent/KernelError.swift → Kernel/Errors/KernelError.swift
- Sources/Core/Agent/KernelCoordination.swift → Kernel/Ports/KernelCoordination.swift
- Sources/Core/Agent/GoalManaging.swift → Kernel/Ports/GoalManaging.swift
- Sources/Core/Agent/KernelClock.swift → Kernel/Ports/KernelClock.swift
- Sources/Events/* → Kernel/Events/*
- Sources/Runtime/AgentRuntime.swift → Runtime/Agent/AgentRuntime.swift
- Sources/Runtime/AgentSession.swift → Runtime/Agent/AgentSession.swift
- Sources/Runtime/ExecutionBoundary.swift → Runtime/Execution/ExecutionBoundary.swift
- Sources/Runtime/M6Orchestrator.swift → Runtime/Planning/M6Orchestrator.swift
- Sources/Runtime/RunLifecycleManager.swift → Runtime/Execution/RunLifecycleManager.swift
- Sources/Runtime/RunRecoveryEngine.swift → Runtime/Execution/RunRecoveryEngine.swift
- Sources/Runtime/M7Contracts.swift → Runtime/Execution/M7Contracts.swift
- Sources/Runtime/M7Stores.swift → Runtime/Execution/M7Stores.swift
- Sources/Modules/Contracts/* → Capabilities/Modules/*
- Sources/Skills/Contracts/* → Capabilities/Skills/*
- Sources/Tools/Contracts/* → Capabilities/Tools/*
- Sources/Providers/Grok/GrokBoundary.swift → Providers/Remote/GrokBoundary.swift
- Sources/Providers/OpenAI/OpenAIBoundary.swift → Providers/Remote/OpenAIBoundary.swift
- Sources/Providers/OpenAICompatible/OpenAICompatibleBoundary.swift → Providers/Remote/OpenAICompatibleBoundary.swift
- Sources/Providers/Local/* → Providers/Local/*
- Sources/cllama/* → Providers/Local/LlamaCPP/*
- Frameworks/llama.xcframework → Providers/Local/LlamaCPP/llama.xcframework
- Sources/Composition/* → Composition/*
- App/PersonalAgent/Screens/* → App/Screens/*
- App/PersonalAgent/RootView.swift → App/Screens/RootView.swift
- App/PersonalAgent/KernelSession.swift → App/Shared/KernelSession.swift
- Tests/PersonalAgentTests/* → Tests/<matching canonical domain>/*; redistribute, do not blind rename.

#### Semantic splits required

- Sources/Foundation/* → Kernel/Contracts/* plus Kernel/Errors/AgentError.swift. No standalone Foundation exists in Issue #85.
- Sources/Core/Cognition/CognitionContracts.swift → Runtime/Observation, Runtime/Planning, Runtime/Verification, Runtime/Result. One file currently spans perception/context, reasoning/planning, action proposal, verification, reflection and state update.
- Sources/Core/Agency/AgencyContracts.swift → Runtime/Observation, Runtime/Verification, Runtime/Result. It spans observation, evaluation and action authorization.
- Sources/Memory/MemoryContracts.swift → Memory/Working, Conversation, LongTerm, Retrieval after type-level ownership review.
- Sources/Memory/FileBackedMemoryStore.swift, InMemoryMemoryStore.swift, MemoryRuntime.swift, MemoryIndex.swift → Memory subdomains according to actual lifecycle/query semantics.
- Sources/Storage/* → Storage/Models, Memory, Configuration, Cache according to actual responsibilities.
- Sources/Composition/ProductPersistenceContracts.swift → Storage/Models, Storage/Memory, Storage/Configuration; it currently mixes session, model metadata, preferences and secrets.
- Sources/Core/Policy/PolicyContracts.swift → candidate Runtime/Verification; consumer evidence still required.
- Sources/Providers/Contracts/* → Provider shared contracts/runtime need provider-by-provider ownership review; do not force all into Remote or Local.
- Sources/Observability/AgentLogger.swift → candidate Kernel/Ports; concrete implementation ownership still needs evidence.
- Sources/Security/SecretStore.swift → split contract vs persistence/network implementation; candidate Kernel/Ports + Storage/Configuration, consumer evidence required.
- Sources/Architecture/ArchitectureManifest.swift → no direct runtime owner established; likely architecture-test/documentation support, not a new production layer.
- App/PersonalAgent/PersonalAgentApp.swift → candidate App/Shared; exact presentation grouping is low-risk.

#### Canonical gaps / deferred ownership decisions

1. Provider shared contract/runtime gap.
2. Foundation gap.
3. Security/network gap.
4. Observability gap.
5. ArchitectureManifest gap.
6. Memory/Storage semantic split.
7. Cognition/Agency/Policy exact file-level split.
8. Test topology redistribution.

**Migration status:** Mapping-only audit **COMPLETE**. Physical migration **DEFERRED** until the ownership gaps above are resolved from import/consumer evidence.

<!-- HANDOFF: Next task resolves ownership gaps from imports/consumers, freezes the file-level map, then begins migration groups. -->
