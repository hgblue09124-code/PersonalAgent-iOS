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


### Audit #14 — Ownership Freeze (evidence-based)

<!-- TASK-CONTEXT: Resolve Audit #13 ownership gaps from actual file responsibilities. No production/test files moved. -->
<!-- DECISION: Ownership follows responsibility, not legacy target names. No new top-level layer is introduced. -->
<!-- INVARIANT: Mixed files are split only when their types have different canonical responsibilities. -->

**Provider contracts — CONFIRMED**
- `LLMProvider.swift`: vendor-neutral provider boundary types (`LLMProvider`, identity/capabilities/request/response/stream/health/lifecycle/selecting) → `Kernel/Ports`; provider binding/credential-resolution types → `Providers/Remote` after semantic split.
- `ProviderRuntime.swift` → `Runtime/Execution/ProviderRuntime.swift`; evidence: owns provider invocation lifecycle, timeout, cancellation and execution events.
- `ProviderRuntimeError.swift` → `Kernel/Ports/Providers/ProviderRuntimeError.swift`; shared provider contract error consumed by Runtime and provider adapters to avoid a SwiftPM dependency cycle.
- `ProviderTransport.swift` → `Providers/Remote/ProviderTransport.swift`; byte-level adapter transport.
- `ChatCompletionsCodec.swift` → `Providers/Remote/ChatCompletionsCodec.swift`; explicitly maps to OpenAI-compatible wire format.
- `HTTPChatProvider.swift` → `Providers/Remote/HTTPChatProvider.swift`.
- `LocalModelContracts.swift`: local inference types → `Providers/Local`; `LocalModelStorage` + `LocalModelStorageError` → `Storage/Models` because they own import/list/delete/active-model persistence.
- `DeterministicFakeProvider.swift` → `Tests/Providers`.

**Foundation — CONFIRMED**
- `AgentError.swift` → `Kernel/Errors/AgentError.swift`.
- `AgentPhase.swift`, `CapabilityLevel.swift`, `Identifiers.swift`, `Provenance.swift`, `SchemaDocument.swift`, `SemanticVersion.swift` → `Kernel/Contracts/*`.
- `DeviceCapabilityContracts.swift` → `Kernel/Ports/DeviceCapability.swift`; it defines a framework-independent device capability port plus deterministic test implementation.
- `Sources/Foundation` is eliminated; no replacement Foundation layer.

**Security / Network — CONFIRMED**
- `SecretStore` + `ProviderCredentialRef` → `Kernel/Ports/Secrets.swift`.
- `NetworkAccess` + request/response/error contracts → `Kernel/Ports/NetworkAccess.swift`.
- `InMemorySecretStore` → `Storage/Configuration`.
- `URLSessionNetworkAccess` → `Storage/Configuration`.
- Provider transport remains `Providers/Remote` and bridges the Kernel network port.

**Observability — CONFIRMED**
- `AgentLogger`, `LogEvent`, `LogLevel`, `AgentPhaseObserving` → `Kernel/Ports/Observability.swift`.
- Concrete logger implementations remain outside Kernel.

**ArchitectureManifest — CONFIRMED**
- `ArchitectureManifest.swift` → `Tests/Composition/ArchitectureManifest.swift`.
- Evidence: it contains allowed-import rules, provider reservations and milestone gates for architecture verification; it is not runtime behavior. No `Architecture/` production layer.

**Memory / Storage — CONFIRMED**
- `MemoryRuntime.swift` → `Memory/Working`; `MemoryIndex.swift` → `Memory/Retrieval`; `InMemoryMemoryStore.swift` → `Memory/Working`; `FileBackedMemoryStore.swift` → `Storage/Memory`.
- `MemoryContracts.swift` requires type-level split; memory semantics stay under `Memory/{Working,Conversation,LongTerm,Retrieval}`, storage-lineage record types move to `Storage/Models`.
- `StorageContracts.swift` → `Storage/Models` for generic record/lineage/revision contracts.
- `PASyncEngine.swift`, `PASyncQueue.swift` → `Storage/Cache` as synchronization/cache infrastructure.

**Cognition / Agency / Policy — CONFIRMED**
- `CognitionContracts.swift`: perception/context → `Runtime/Observation`; reasoning/planning → `Runtime/Planning`; action proposal → `Runtime/Execution`; verification → `Runtime/Verification`; reflection/state update → `Runtime/Result`.
- `AgencyContracts.swift`: observation/evaluation → `Runtime/Observation`; action authorization → `Runtime/Verification`; continuation/result → `Runtime/Result`.
- `PolicyContracts.swift` → `Runtime/Verification`; evidence: policy authorizes/denies actions at the guard boundary.
- No `Cognition`, `Agency`, or `Policy` production folders survive canonical migration.

**Composition persistence — CONFIRMED**
- `ProductPersistenceContracts.swift`: model metadata → `Storage/Models`; session data → `Storage/Memory`; preferences/secrets configuration → `Storage/Configuration`; `ProductPersistenceContainer` remains `Composition`.

**Ownership freeze:** all Audit #13 unresolved ownership groups now have a canonical destination. Remaining work is migration mechanics, Package.swift target updates, and verification—not further architecture discovery.

<!-- HANDOFF: Ownership is frozen. Next task starts physical migration with Kernel contracts/errors/ports, then build/test/audit before the next group. -->


### Migration Checkpoint #1 — Kernel Agent Group

<!-- TASK-CONTEXT: Issue #85 physical migration checkpoint. -->
<!-- DECISION: The legacy Sources/Core/Agent group is replaced by Kernel/{Contracts,Errors,Ports}; PAKernel now targets Kernel. -->
<!-- INVARIANT: Migration must preserve behavior; path-sensitive architecture tests are updated only to reflect the canonical tree. -->

**CONFIRMED**
- Moved 7 Kernel agent files from `Sources/Core/Agent` into canonical subdomains:
  - `Kernel/Contracts/{KernelContracts,LifecycleMachine,GoalMachine}.swift`
  - `Kernel/Errors/KernelError.swift`
  - `Kernel/Ports/{GoalManaging,KernelClock,KernelCoordination}.swift`
- Updated `Package.swift` so `PAKernel` targets `Kernel`.
- Updated repository integrity / Kernel isolation audit tests to inspect canonical paths.
- No provider, runtime, UI, or behavior logic was changed.
- First CI run exposed only stale path assertions; minimal test-path repair was applied.
- Final CI: Swift package tests **PASS** (346 tests / 47 suites); repository integrity **PASS**; iOS arm64 build + unsigned IPA **PASS**.

**DEFERRED**
- Foundation elimination remains a later migration group; current Kernel still consumes the existing PAFoundation target.
- Kernel Events remain in the legacy Events group until their dedicated migration checkpoint.

<!-- HANDOFF: Next task migrates Foundation contracts/errors into Kernel and removes the legacy Foundation layer only when all consumers are updated. -->


### Migration Checkpoint #5 — Provider Ownership Migration

**CONFIRMED**
- Vendor-neutral provider contracts now live under `Kernel/Ports/Providers`; the existing `PAProviders` module is retained as the provider-contract target while physical ownership follows Kernel Ports.
- Provider binding and credential-resolution types are separated into `Providers/Remote/Shared/ProviderCredentials.swift`.
- `ProviderRuntimeError` is owned by `Kernel/Ports/Providers` so Runtime and remote provider adapters share the contract without introducing a dependency cycle.
- Local inference contracts are separated from local-model persistence contracts.
- Local provider implementation is physically under `Providers/Local`; local model persistence is under `Storage/Models`.
- Deterministic provider fake is test-only under `Tests/Providers`.
- llama.cpp wrapper sources/framework are physically under `Providers/Local/LlamaCPP`.

**Verification required**
- Swift package tests, repository integrity, import-boundary checks, iOS arm64 unsigned build, then post-migration audit.


### Migration Checkpoint #5 Audit Repair — CONFIRMED

- Repository integrity assertions were stale after the provider ownership migration and still referenced removed `Providers/Contracts/*` paths.
- Updated assertions to the canonical provider contract path under `Kernel/Ports/Providers` and the test-only fake under `Tests/Providers`.
- Updated the ownership record for `ProviderRuntimeError` to match the verified dependency-safe location.
- CI for the repair commit is pending and remains **CHƯA XÁC MINH** until the new workflow completes.
