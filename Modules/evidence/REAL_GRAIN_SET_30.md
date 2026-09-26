# Real Grain Set — 30 Evidence-Backed Grains

This file contains 30 independent cognitive grains. The file is only the persistence container; each heading/section is a separate semantic grain.

## G-024 — M7 architecture freeze

ID: m7-architecture-frozen

PURPOSE
Freeze durable run/session lifecycle semantics before runtime implementation.

WHEN
A milestone introduces durable execution and recovery contracts.

RULE
Freeze lifecycle, checkpoint, recovery, lease, provenance, and state-authority contracts before implementation.

VERIFY
PR #24 defined the M7.0 architecture with zero production Swift runtime changes.

STATUS: CONFIRMED

SOURCE
PR #24 — M7.0 Architecture Specification Frozen

## G-026 — Evidence resolution contract

ID: evidence-resolution-contract

PURPOSE
Keep ambiguous execution outcomes from being silently treated as success or failure.

WHEN
Execution completion conflicts with unavailable or unresolved evidence.

RULE
Use explicit evidence-resolution and unresolved dispositions; preserve stable EventID binding and idempotent event append semantics.

VERIFY
PR #26 defined the final M7.0 recovery semantics repair.

STATUS: CONFIRMED

SOURCE
PR #26

## G-027 — Durable run lifecycle

ID: durable-run-lifecycle

PURPOSE
Implement durable execution without moving state authority.

WHEN
Building production durable run lifecycle support.

RULE
Keep AgentRuntime as sole AgentState/goal authority while stores, checkpoints, leases, evidence resolution, and recovery coordinate around it.

VERIFY
PR #27 implemented the M7.1 runtime foundation and its test suites.

STATUS: CONFIRMED

SOURCE
PR #27

## G-029 — Recovery fail closed

ID: recovery-fail-closed

PURPOSE
Preserve uncertainty during runtime recovery.

WHEN
A target throws, times out, loses network, or recovery lacks definitive evidence.

RULE
Do not collapse UNKNOWN/UNAVAILABLE into FAILED or NOT_STARTED; use capability-aware recovery and stable WAL EventID replay.

VERIFY
PR #29 reports 274 unit/integration tests passing.

STATUS: CONFIRMED

SOURCE
PR #29

## G-031 — Execution truth

ID: execution-truth

PURPOSE
Keep durable mutation evidence aligned with execution state.

WHEN
Recovery must determine whether a mutation happened across a crash boundary.

RULE
Persist mutation evidence and reconcile the state journal against the authoritative runtime; executor success and evidence are separate facts.

VERIFY
PR #31 covers crash-window, restart, target-bound evidence, and contradiction tests.

STATUS: CONFIRMED

SOURCE
PR #31

## G-032 — M8 product boundaries

ID: m8-product-boundaries

PURPOSE
Keep iOS product boundaries explicit around session, local model, device capability, and persistence.

WHEN
Connecting application code to local-model and device infrastructure.

RULE
Expose narrow application boundaries and compose them through M8CompositionRoot instead of letting UI own infrastructure.

VERIFY
PR #32 introduced the four dedicated product boundaries with tests and documentation.

STATUS: CONFIRMED

SOURCE
PR #32

## G-034 — GGUF vertical slice

ID: gguf-vertical-slice

PURPOSE
Define the minimum complete path for native GGUF inference.

WHEN
Adding real local inference support.

RULE
Keep parsing, residency, engine lifecycle, streaming, cancellation, thermal/memory governance, and provider adaptation behind PAProvidersLocal.

VERIFY
PR #34 added coverage for those lifecycle and governance concerns.

STATUS: CONFIRMED

SOURCE
PR #34

## G-036 — Native llama runtime

ID: native-llama-runtime

PURPOSE
Replace simulated inference with the real native runtime while preserving vendor isolation.

WHEN
A local inference prototype needs production-native execution.

RULE
Integrate the official llama.cpp native target behind PAProvidersLocal and retain single-resident-model coordination.

VERIFY
PR #36 wires native llama C APIs and deterministic resource release.

STATUS: CONFIRMED

SOURCE
PR #36

## G-039 — Platform-conditioned cllama

ID: platform-conditioned-native-runtime

PURPOSE
Keep native C/C++ inference dependencies compatible with platform-neutral CI.

WHEN
An Apple-only native dependency enters a Swift package.

RULE
Condition the native dependency to Apple platforms and retain a dedicated Apple build lane.

VERIFY
PR #39 reports Linux CI green plus Apple native build/IPA and native inference repair.

STATUS: CONFIRMED

SOURCE
PR #39

## G-041 — App/provider dependency

ID: app-provider-dependency

PURPOSE
Make the real local inference dependency graph explicit at composition.

WHEN
The app composition root constructs a real local provider.

RULE
Declare PAComposition → PAProvidersLocal in package and architecture rules; wire the adapter through composition.

VERIFY
PR #41 reports the compiled dependency chain and real-inference test reporting repair.

STATUS: CONFIRMED

SOURCE
PR #41

## G-058 — Local model capabilities

ID: local-model-capabilities

PURPOSE
Expose local model lifecycle without moving provider ownership into UI.

WHEN
Settings needs model import, installed-model state, load/unload, or capability visibility.

RULE
Keep storage/lifecycle in application/runtime boundaries and route active local completion through DynamicActiveProvider.

VERIFY
PR #58 added lifecycle/storage wiring plus unit and integration coverage.

STATUS: CONFIRMED

SOURCE
PR #58

## G-061 — M9 forensic audit

ID: m9-forensic-audit

PURPOSE
Separate verified M9 facts from assumptions before adding execution behavior.

WHEN
Starting a milestone whose physical execution path is not yet proven.

RULE
Audit current main and contracts first; do not treat planned architecture as implemented behavior.

VERIFY
PR #61 is explicitly a forensic architecture audit with no production code changes.

STATUS: CONFIRMED

SOURCE
PR #61

## G-063 — Real GGUF verification

ID: real-gguf-verification

PURPOSE
Prove the actual local GGUF call graph rather than assuming model load implies execution.

WHEN
Verifying a real local agent path.

RULE
Trace storage → runtime coordination → native engine → provider adapter → output validation and test failure geometries independently.

VERIFY
PR #63 reports automated verification of failure geometries F1–F7.

STATUS: CONFIRMED

SOURCE
PR #63

## G-065 — GGUF document type

ID: gguf-document-type

PURPOSE
Make iOS receive .gguf files through the system document flow.

WHEN
The app must import GGUF files from Files or another document provider.

RULE
Register the GGUF UTI/document type and restrict the importer to the .gguf content type.

VERIFY
PR #65 records Info.plist registration, Xcode wiring, importer restriction, and evidence documentation.

STATUS: CONFIRMED

SOURCE
PR #65

## G-066 — Provider vertical slice

ID: provider-vertical-slice

PURPOSE
Keep remote provider execution explicit and fail closed on invalid completion output.

WHEN
A provider path is being proven independently from local inference.

RULE
Verify provider requirements end-to-end and reject empty completion text.

VERIFY
PR #66 added P1–P7 coverage and fail-closed empty-completion handling.

STATUS: CONFIRMED

SOURCE
PR #66

## G-073 — Dev model download

ID: dev-model-download

PURPOSE
Provide a bounded development path for installing a lightweight public GGUF model.

WHEN
Developers need a reproducible small model for iPhone testing.

RULE
Keep the path dev-only; verify download size and SHA-256 before using model storage.

VERIFY
PR #73 specifies a 350 MB hard limit and SHA-256 verification; failed validation never installs.

STATUS: CONFIRMED

SOURCE
PR #73

## G-075 — Native Agent UI beta

ID: native-agent-ui-beta

PURPOSE
Establish an Agent-first native UI without redesigning backend/runtime ownership.

WHEN
Building the first coherent iOS Agent experience.

RULE
Use native SwiftUI presentation and progressive disclosure while preserving application boundaries.

VERIFY
PR #75 explicitly excludes backend/runtime, llama.cpp/provider, and security-hardening redesign.

STATUS: CONFIRMED

SOURCE
PR #75

## G-077 — Goal to local LLM bridge

ID: goal-to-local-llm-bridge

PURPOSE
Close the application-layer gap between an accepted goal and real local LLM execution.

WHEN
Chat accepts a goal but orchestration stops at proposed state.

RULE
Trigger M6Orchestrator from KernelSession and route reasoning through DynamicActiveProvider/local GGUF; empty reasoning fails closed.

VERIFY
PR #77 defines the acceptance call graph and leaves lifecycle/UI/storage/M7 governance unchanged.

STATUS: CONFIRMED

SOURCE
PR #77

## G-078 — IPA verification

ID: ipa-verification

PURPOSE
Make Apple build artifacts independently verifiable for physical iPhone testing.

WHEN
CI produces an unsigned development IPA.

RULE
Harden IPA verification so every Apple build yields a verifiably valid artifact; keep runtime changes separate.

VERIFY
PR #78 is explicitly agent/IPA verification work with no runtime/product changes.

STATUS: CONFIRMED

SOURCE
PR #78

## G-079 — Authoritative Agent progress

ID: authoritative-agent-progress

PURPOSE
Show real execution progress without introducing a second runtime state machine.

WHEN
Local GGUF execution works but Chat lacks execution narrative/result.

RULE
Use authoritative M6Orchestrator callbacks for reasoning/action/observation/evaluation and final result.

VERIFY
PR #79 explicitly preserves lifecycle/local-model boundaries and rejects a second runtime.

STATUS: CONFIRMED

SOURCE
PR #79

## G-081 — Native Agent experience

ID: native-agent-experience

PURPOSE
Make the Agent UI user-facing instead of exposing permanent technical milestone state.

WHEN
The backend works but the primary UX is infrastructure-oriented.

RULE
Use Agent-first task presentation and progressive disclosure while preserving runtime/provider/local-model/storage boundaries.

VERIFY
PR #81 explicitly forbids direct llama.cpp/provider/storage access from UI.

STATUS: CONFIRMED

SOURCE
PR #81

## G-086 — Canonical layers

ID: canonical-layer-structure

PURPOSE
Give the repository one explicit physical architecture axis.

WHEN
The repository contains overlapping legacy source locations.

RULE
Use Kernel, Runtime, Capabilities, Providers, Memory, Storage, Composition, App, and Tests as canonical domains; keep structural migration separate from behavior redesign.

VERIFY
PR #86 moved 79 source files and preserved module/product boundaries.

STATUS: CONFIRMED

SOURCE
PR #86

## G-087 — Executable architecture contract

ID: executable-architecture-contract

PURPOSE
Keep architecture documentation synchronized with verified repository reality.

WHEN
A major architecture migration reaches a green recovery baseline.

RULE
Document current reality, target boundaries, contracts, operations, and ADRs from verified evidence.

VERIFY
PR #87 is documentation-only and based on verified green baseline e3e7182.

STATUS: CONFIRMED

SOURCE
PR #87

## G-088 — Runtime/event atomicity

ID: runtime-event-atomicity

PURPOSE
Prevent terminal state from being committed when its authoritative event cannot be appended.

WHEN
A lifecycle transition depends on an authoritative event append.

RULE
Treat state/event publication as one semantic boundary and add regression coverage for append failure.

VERIFY
PR #88 is scoped to terminal lifecycle goal/event atomicity and its failure regression.

STATUS: CONFIRMED

SOURCE
PR #88

## G-089 — Kernel migration boundary

ID: kernel-migration-boundary

PURPOSE
Move Kernel agent sources physically without redesigning behavior.

WHEN
Executing the canonical Kernel migration group.

RULE
Move sources into Kernel/{Contracts,Errors,Ports}, update SPM paths, and block the next group until CI/build/tests are green and audited.

VERIFY
PR #89 defines the migration scope and validation gate.

STATUS: CONFIRMED

SOURCE
PR #89

## G-090 — Foundation/event contracts

ID: foundation-event-contract-migration

PURPOSE
Consolidate Foundation, event, and module execution port contracts under Kernel ownership.

WHEN
A contract belongs to the lowest stable architectural layer.

RULE
Move contracts toward Kernel while retaining compatibility bridges when needed; do not redesign product behavior during physical migration.

VERIFY
PR #90 explicitly scopes the migration and compatibility bridges.

STATUS: CONFIRMED

SOURCE
PR #90

## G-091 — Cognition/Policy runtime ownership

ID: cognition-policy-runtime-ownership

PURPOSE
Place Cognition and Policy contracts under canonical Runtime ownership.

WHEN
Contracts are physically outside the runtime that owns their semantics.

RULE
Move Cognition into Runtime ownership and Policy into Runtime/Verification; remove legacy targets only as part of that migration.

VERIFY
PR #91 records the ownership migration with preserved behavior.

STATUS: CONFIRMED

SOURCE
PR #91

## G-092 — Compact Markdown protocol

ID: compact-markdown-knowledge-protocol

PURPOSE
Make Markdown a durable agent knowledge surface without turning it into a session diary.

WHEN
Architecture work needs persistent human-readable agent state.

RULE
Keep handoff/audit/work-log/lessons complementary and record durable evidence-backed knowledge.

VERIFY
PR #92 refreshed post-merge state and formalized the compact Markdown knowledge protocol.

STATUS: CONFIRMED

SOURCE
PR #92

## G-093 — CI check consolidation

ID: ci-check-consolidation

PURPOSE
Reduce duplicate CI notifications without weakening verification.

WHEN
Multiple CI jobs perform the same logical check.

RULE
Consolidate duplicate checks only when existing tests and integrity assertions remain unchanged; retain distinct Apple native evidence.

VERIFY
PR #93 explicitly preserves assertions and keeps Apple Native Build separate.

STATUS: CONFIRMED

SOURCE
PR #93

## G-094 — Capabilities migration gate

ID: capabilities-migration-gate

PURPOSE
Move Modules, Skills, and Tools into canonical Capabilities ownership without behavior rewrite.

WHEN
Executing the Capabilities physical migration group.

RULE
Move paths, update Package.swift and path-sensitive CI/tests, then require the full verification gate.

VERIFY
PR #94 reports 340 tests across 46 suites and Apple/IPA verification.

STATUS: CONFIRMED

SOURCE
PR #94


# Additional Real Grains — Expanded to 100

## G-031 — Native llama.cpp XCFramework

ID: g043-native-xcframework

PURPOSE
Use the official native llama.cpp XCFramework when the local runtime requires Apple-native integration.

WHEN
When the Apple local inference runtime needs the native llama implementation.

RULE
Keep the native framework integration behind the local provider boundary.

VERIFY
PR #43 is the dedicated official llama.cpp XCFramework integration.

STATUS: CONFIRMED

SOURCE
PR #43

## G-032 — Local GGUF runtime slice

ID: g045-local-runtime-vertical-slice

PURPOSE
Prove the local GGUF runtime as a complete vertical slice rather than isolated pieces.

WHEN
When implementing the M8.2 local model runtime.

RULE
Verify the end-to-end runtime path before treating the feature as complete.

VERIFY
PR #45 is titled M8.2 Local GGUF Model Runtime Vertical Slice.

STATUS: CONFIRMED

SOURCE
PR #45

## G-033 — Runtime particle reuse audit

ID: g047-runtime-particle-audit

PURPOSE
Reuse proven runtime components instead of inventing parallel implementations.

WHEN
When extending an existing local runtime.

RULE
Audit proven runtime particles before adding new execution machinery.

VERIFY
PR #47 is explicitly a proven runtime particle reuse audit.

STATUS: CONFIRMED

SOURCE
PR #47

## G-034 — Local model storage foundation

ID: g049-local-model-storage

PURPOSE
Give installed GGUF models a durable storage boundary.

WHEN
When adding persistent local model installation.

RULE
Keep model storage explicit and separate from inference execution.

VERIFY
PR #49 is the local GGUF storage foundation.

STATUS: CONFIRMED

SOURCE
PR #49

## G-035 — Active GGUF binding

ID: g051-active-gguf-binding

PURPOSE
Bind the selected GGUF model to the native runtime through a defined active-model path.

WHEN
When a stored model becomes the runtime's active model.

RULE
Make active-model binding explicit rather than letting UI select an engine directly.

VERIFY
PR #51 is titled bind active GGUF model to llama runtime.

STATUS: CONFIRMED

SOURCE
PR #51

## G-036 — Verified local result

ID: g053-verified-local-result

PURPOSE
Represent local-engine completion as an explicitly verified result.

WHEN
When local inference returns an output that must be trusted by orchestration.

RULE
Do not equate engine completion with verified application result.

VERIFY
PR #53 is dedicated to an explicit verified result for the local engine.

STATUS: CONFIRMED

SOURCE
PR #53

## G-037 — Physical device verification audit

ID: g055-physical-device-audit

PURPOSE
Separate physical-device verification status from code-level runtime claims.

WHEN
When local inference is claimed to work on iPhone.

RULE
Record whether execution was actually verified on the physical target.

VERIFY
PR #55 is a physical device verification status audit.

STATUS: CONFIRMED

SOURCE
PR #55

## G-038 — Commit 4 repair blocks

ID: g059-commit4-repair-blocks

PURPOSE
Resolve identified repair blocks as a bounded follow-up rather than broad redesign.

WHEN
When a prior local-model capability commit has known repair blocks.

RULE
Repair the named blocks and preserve the existing capability boundary.

VERIFY
PR #59 is explicitly the four remaining repair blocks for Commit 4.

STATUS: CONFIRMED

SOURCE
PR #59

## G-039 — CI Node 24 migration

ID: g062-actions-node24

PURPOSE
Keep GitHub Actions runtimes current when the CI platform deprecates an older Node version.

WHEN
When CI reports a Node runtime deprecation.

RULE
Upgrade the affected action versions without mixing unrelated product changes.

VERIFY
PR #62 upgrades GitHub Actions to Node 24 versions.

STATUS: CONFIRMED

SOURCE
PR #62

## G-040 — GGUF document picker boundary

ID: g067-document-picker-boundary

PURPOSE
Keep GGUF selection at the document-picker boundary.

WHEN
When the system picker returns a GGUF selection.

RULE
Normalize the picker handoff at the app boundary before runtime handling.

VERIFY
PR #67 explicitly aligns the document picker boundary for GGUF selection.

STATUS: CONFIRMED

SOURCE
PR #67

## G-041 — Universal file import handoff probe

ID: g068-file-import-handoff-probe

PURPOSE
Instrument the system-file-to-app handoff when import delivery is uncertain.

WHEN
When a file appears in Files but the app does not receive the selection.

RULE
Probe the handoff boundary before changing model or storage logic.

VERIFY
PR #68 adds a universal file import handoff probe.

STATUS: CONFIRMED

SOURCE
PR #68

## G-042 — Agent-native UI foundation

ID: g069-agent-native-ui-foundation

PURPOSE
Keep the first native Agent UI focused on the Agent experience.

WHEN
When replacing infrastructure-first presentation with a native Agent surface.

RULE
Build presentation around Agent tasks while preserving backend boundaries.

VERIFY
PR #69 establishes the M10.0 Agent-Native UI foundation.

STATUS: CONFIRMED

SOURCE
PR #69

## G-043 — Agent runtime controls

ID: g070-runtime-controls

PURPOSE
Expose runtime controls through Settings without taking runtime ownership into UI.

WHEN
When Settings needs Agent runtime controls.

RULE
Route controls through the existing application boundary.

VERIFY
PR #70 expands Agent runtime controls.

STATUS: CONFIRMED

SOURCE
PR #70

## G-044 — Composition task routing

ID: g071-composition-task-routing

PURPOSE
Route Agent task execution through Composition rather than direct UI orchestration.

WHEN
When UI initiates an Agent task.

RULE
UI requests work through Composition; it does not own execution infrastructure.

VERIFY
PR #71 explicitly routes Agent task execution through the Composition boundary.

STATUS: CONFIRMED

SOURCE
PR #71

## G-045 — Lifecycle command gating

ID: g072-lifecycle-command-gating

PURPOSE
Prevent runtime commands from being issued in invalid lifecycle states.

WHEN
When Settings exposes Agent runtime commands.

RULE
Gate commands by lifecycle state before execution.

VERIFY
PR #72 explicitly gates Agent runtime commands by lifecycle.

STATUS: CONFIRMED

SOURCE
PR #72

## G-046 — Progressive native UI

ID: g075-progressive-native-ui

PURPOSE
Use progressive disclosure for the native Agent experience.

WHEN
When presenting Agent capabilities without exposing infrastructure details permanently.

RULE
Show task-relevant information first and technical detail progressively.

VERIFY
PR #75 establishes the native Agent beta UI foundation.

STATUS: CONFIRMED

SOURCE
PR #75

## G-047 — Accepted goal to execution

ID: g077-goal-accepted-execution

PURPOSE
Connect an accepted Agent goal to actual local LLM execution.

WHEN
When a goal is accepted but orchestration stops before model execution.

RULE
Route accepted goals through the composition/orchestration path to the active local provider.

VERIFY
PR #77 closes the Agent goal to local LLM execution bridge.

STATUS: CONFIRMED

SOURCE
PR #77

## G-048 — IPA pre-release verification

ID: g078-ipa-prerelease-verification

PURPOSE
Verify generated IPA artifacts independently of runtime behavior.

WHEN
When CI publishes an unsigned development IPA.

RULE
Treat artifact validity as a separate verification concern.

VERIFY
PR #78 optimizes AGENTS.md and IPA pre-release verification.

STATUS: CONFIRMED

SOURCE
PR #78

## G-049 — Live execution result

ID: g079-live-execution-result

PURPOSE
Expose live Agent execution progress and final result from authoritative execution callbacks.

WHEN
When the Agent is executing and the UI needs progress.

RULE
Use authoritative execution callbacks instead of creating a second execution state machine.

VERIFY
PR #79 adds live Agent execution progress and result.

STATUS: CONFIRMED

SOURCE
PR #79

## G-050 — Canonical repository layers

ID: g086-canonical-repository-layers

PURPOSE
Use one explicit physical architecture axis for repository domains.

WHEN
When source locations overlap or legacy layouts remain.

RULE
Migrate structure without changing behavior at the same time.

VERIFY
PR #86 consolidates the repository into canonical layers.

STATUS: CONFIRMED

SOURCE
PR #86

## G-051 — Architecture reality contract

ID: g087-architecture-reality-contract

PURPOSE
Document architecture from verified repository reality.

WHEN
When a major migration reaches a verified baseline.

RULE
Do not document planned structure as implemented structure.

VERIFY
PR #87 establishes the executable architecture contract.

STATUS: CONFIRMED

SOURCE
PR #87

## G-052 — State event boundary

ID: g088-state-event-boundary

PURPOSE
Treat terminal state and authoritative event publication as one semantic boundary.

WHEN
When a lifecycle transition depends on an event append.

RULE
Reject partial publication when the authoritative event cannot be appended.

VERIFY
PR #88 preserves runtime state/event atomicity.

STATUS: CONFIRMED

SOURCE
PR #88

## G-053 — Kernel source move

ID: g089-kernel-source-move

PURPOSE
Move Kernel agent sources into the canonical Kernel tree without behavior redesign.

WHEN
When executing the Kernel migration group.

RULE
Keep physical migration separate from behavioral change.

VERIFY
PR #89 migrates Kernel agent sources to the canonical Kernel tree.

STATUS: CONFIRMED

SOURCE
PR #89

## G-054 — Foundation contract move

ID: g090-foundation-contract-move

PURPOSE
Move Foundation contracts toward Kernel ownership.

WHEN
When a lowest-level contract is physically outside Kernel.

RULE
Relocate ownership while retaining required compatibility bridges.

VERIFY
PR #90 migrates Foundation and event contracts toward Kernel.

STATUS: CONFIRMED

SOURCE
PR #90

## G-055 — Event contract ownership

ID: g090-event-contract-move

PURPOSE
Place event contracts under the stable Kernel contract boundary.

WHEN
When event definitions belong to the lowest stable layer.

RULE
Keep event contract migration separate from product behavior redesign.

VERIFY
PR #90 explicitly includes event contracts in the Kernel migration.

STATUS: CONFIRMED

SOURCE
PR #90

## G-056 — Migration compatibility bridge

ID: g090-compatibility-bridge

PURPOSE
Use temporary compatibility bridges when physical contract migration would otherwise break consumers.

WHEN
When moving contracts across canonical layers.

RULE
Preserve consumers during migration but do not turn bridges into new architecture.

VERIFY
PR #90 explicitly scopes compatibility bridges.

STATUS: CONFIRMED

SOURCE
PR #90

## G-057 — Cognition runtime ownership

ID: g091-cognition-runtime

PURPOSE
Place Cognition contracts under Runtime ownership.

WHEN
When cognition semantics are physically outside Runtime.

RULE
Move ownership to Runtime while preserving behavior.

VERIFY
PR #91 moves Cognition into Runtime ownership.

STATUS: CONFIRMED

SOURCE
PR #91

## G-058 — Policy verification ownership

ID: g091-policy-verification

PURPOSE
Place Policy verification under Runtime/Verification ownership.

WHEN
When policy semantics belong to Runtime verification.

RULE
Keep policy ownership explicit in the canonical Runtime structure.

VERIFY
PR #91 moves Policy into Runtime/Verification.

STATUS: CONFIRMED

SOURCE
PR #91

## G-059 — Markdown cognitive state

ID: g092-markdown-state

PURPOSE
Use Markdown as persistent cognitive state rather than generated documentation.

WHEN
When Agent work needs durable human-readable state.

RULE
Persist meaningful state in Markdown and keep it readable by humans.

VERIFY
PR #92 synchronizes the Markdown Agent protocol.

STATUS: CONFIRMED

SOURCE
PR #92

## G-060 — Complementary Markdown surfaces

ID: g092-complementary-markdown-surfaces

PURPOSE
Keep handoff, audit, work-log, and lessons complementary.

WHEN
When maintaining Agent memory files.

RULE
Avoid duplicating the same session information across Markdown surfaces.

VERIFY
PR #92 formalizes the compact Markdown Agent protocol.

STATUS: CONFIRMED

SOURCE
PR #92

## G-061 — Duplicate CI check consolidation

ID: g093-duplicate-check-consolidation

PURPOSE
Consolidate duplicate logical CI checks without removing distinct verification.

WHEN
When multiple jobs report the same logical check.

RULE
Remove notification duplication while preserving test and integrity assertions.

VERIFY
PR #93 consolidates duplicate check notifications.

STATUS: CONFIRMED

SOURCE
PR #93

## G-062 — Apple evidence retained

ID: g093-apple-evidence-retained

PURPOSE
Keep Apple native build evidence distinct during CI consolidation.

WHEN
When consolidating CI checks in a cross-platform project.

RULE
Do not merge away the Apple-specific native verification signal.

VERIFY
PR #93 explicitly retains the Apple Native Build check.

STATUS: CONFIRMED

SOURCE
PR #93

## G-063 — Capabilities path migration

ID: g094-capabilities-path-migration

PURPOSE
Move executable capability groups into canonical Capabilities ownership.

WHEN
When migrating the repository's capability layout.

RULE
Move paths first and preserve behavior.

VERIFY
PR #94 migrates the Capabilities group to the canonical layout.

STATUS: CONFIRMED

SOURCE
PR #94

## G-064 — Package path update

ID: g094-package-path-update

PURPOSE
Update package and path-sensitive references after a physical capability migration.

WHEN
When source paths move under Capabilities.

RULE
Change path references as part of the same migration and verify the complete package.

VERIFY
PR #94 explicitly includes the Capabilities migration gate.

STATUS: CONFIRMED

SOURCE
PR #94

## G-065 — Capabilities full gate

ID: g094-full-verification-gate

PURPOSE
Require the full verification gate after physical capability migration.

WHEN
When a canonical capability migration is complete.

RULE
Do not declare migration complete from source movement alone.

VERIFY
PR #94 reports 340 tests across 46 suites and Apple/IPA verification.

STATUS: CONFIRMED

SOURCE
PR #94

## G-066 — Dynamic active provider

ID: g058-active-provider

PURPOSE
Route active local completion through the selected provider boundary.

WHEN
When Settings changes the active local model.

RULE
Keep provider selection separate from UI rendering.

VERIFY
PR #58 adds local model capabilities and active-provider routing.

STATUS: CONFIRMED

SOURCE
PR #58

## G-067 — Local failure geometries

ID: g063-failure-geometries

PURPOSE
Test distinct local execution failure geometries instead of only the happy path.

WHEN
When verifying real GGUF execution.

RULE
Exercise failure cases independently so a passing load test cannot mask execution defects.

VERIFY
PR #63 reports automated F1–F7 verification.

STATUS: CONFIRMED

SOURCE
PR #63

## G-068 — GGUF UTI registration

ID: g065-uti-registration

PURPOSE
Register GGUF as a document type recognized by the iOS app.

WHEN
When Files must hand a GGUF document to the app.

RULE
Declare the document type at the app boundary.

VERIFY
PR #65 registers the GGUF document type in Info.plist.

STATUS: CONFIRMED

SOURCE
PR #65

## G-069 — Provider empty completion fail-closed

ID: g066-empty-provider-fail-closed

PURPOSE
Reject an empty provider completion instead of treating it as a successful answer.

WHEN
When a remote provider returns no completion text.

RULE
An empty completion is an invalid execution result.

VERIFY
PR #66 adds fail-closed empty-completion handling.

STATUS: CONFIRMED

SOURCE
PR #66

## G-070 — Model download integrity

ID: g073-download-integrity

PURPOSE
Verify downloaded development models before installation.

WHEN
When a development model is fetched from a remote source.

RULE
Check bounded size and SHA-256 before storing the model.

VERIFY
PR #73 specifies a 350 MB hard limit and SHA-256 verification.

STATUS: CONFIRMED

SOURCE
PR #73

## G-071 — Development-only model path

ID: g073-dev-only-model-path

PURPOSE
Keep the lightweight model download path bounded to development use.

WHEN
When developers need a reproducible test model.

RULE
Do not turn a dev convenience path into unrestricted production model distribution.

VERIFY
PR #73 is explicitly a dev-model feature.

STATUS: CONFIRMED

SOURCE
PR #73

## G-072 — Audit before execution

ID: g061-audit-before-execution

PURPOSE
Audit current contracts before adding execution behavior.

WHEN
When a milestone's physical execution path is uncertain.

RULE
Separate verified current reality from planned architecture.

VERIFY
PR #61 is an architecture and contract audit with no production code changes.

STATUS: CONFIRMED

SOURCE
PR #61

## G-073 — No-code forensic audit

ID: g061-no-code-audit

PURPOSE
Use a no-production-code audit when the immediate need is to establish truth.

WHEN
When architecture claims are ahead of verified implementation.

RULE
Do not change production code merely to make an audit appear complete.

VERIFY
PR #61 is explicitly an audit-only milestone.

STATUS: CONFIRMED

SOURCE
PR #61

## G-074 — Device status evidence

ID: g055-device-status

PURPOSE
Record physical-device status explicitly during local runtime validation.

WHEN
When CI and source inspection cannot prove iPhone execution.

RULE
Treat physical-device evidence as its own verification category.

VERIFY
PR #55 is dedicated to physical device verification status.

STATUS: CONFIRMED

SOURCE
PR #55

## G-075 — Storage/runtime separation

ID: g049-storage-runtime-separation

PURPOSE
Keep local model persistence separate from runtime execution.

WHEN
When installing or selecting local models.

RULE
Storage owns persistence; runtime owns execution.

VERIFY
PR #49 establishes local GGUF storage and PR #51 binds the active model to runtime.

STATUS: CONFIRMED

SOURCE
PR #49/#51

## G-076 — Selected model state

ID: g051-selected-model

PURPOSE
Represent the selected active GGUF model explicitly.

WHEN
When multiple installed models can exist.

RULE
Separate installed-model inventory from the active runtime selection.

VERIFY
PR #51 binds the active GGUF model to the llama runtime.

STATUS: CONFIRMED

SOURCE
PR #51

## G-077 — Verified result contract

ID: g053-result-contract

PURPOSE
Expose local engine output through an explicit verified-result contract.

WHEN
When the engine returns text that orchestration must consume.

RULE
Verification status must be represented separately from raw engine completion.

VERIFY
PR #53 is dedicated to explicit verified local-engine results.

STATUS: CONFIRMED

SOURCE
PR #53

## G-078 — Native vendor isolation

ID: g043-vendor-isolation

PURPOSE
Keep native llama implementation isolated behind the local provider.

WHEN
When integrating vendor C/C++ inference code.

RULE
Do not spread native vendor APIs across application layers.

VERIFY
PR #43 integrates the official llama.cpp XCFramework as a native runtime change.

STATUS: CONFIRMED

SOURCE
PR #43

## G-079 — Governed local inference

ID: g034-governed-local-inference

PURPOSE
Treat streaming, cancellation, residency, thermal and memory constraints as part of local inference.

WHEN
When implementing real on-device inference.

RULE
A local inference path is incomplete without lifecycle and resource governance.

VERIFY
PR #34 defines the GGUF local inference vertical slice.

STATUS: CONFIRMED

SOURCE
PR #34

## G-080 — Native resource release

ID: g036-resource-release

PURPOSE
Release native llama resources deterministically.

WHEN
When loading/unloading the native inference engine.

RULE
Tie native resource lifetime to explicit runtime lifecycle.

VERIFY
PR #36 records deterministic native llama resource release.

STATUS: CONFIRMED

SOURCE
PR #36

## G-081 — Apple native verification lane

ID: g039-apple-lane

PURPOSE
Keep an Apple-native verification lane for platform-specific inference code.

WHEN
When the package contains Apple-only native dependencies.

RULE
Linux package verification cannot replace Apple-native verification.

VERIFY
PR #39 reports Linux CI plus Apple native build/IPA verification.

STATUS: CONFIRMED

SOURCE
PR #39

## G-082 — Composition dependency declaration

ID: g041-composition-dependency

PURPOSE
Declare the local provider dependency at Composition rather than hiding it in UI.

WHEN
When the app composition root constructs the local provider.

RULE
Make the dependency graph explicit in package and architecture boundaries.

VERIFY
PR #41 repairs the app dependency graph for real inference.

STATUS: CONFIRMED

SOURCE
PR #41

## G-083 — Settings capability boundary

ID: g058-settings-boundary

PURPOSE
Let Settings expose model capabilities without owning model infrastructure.

WHEN
When Settings needs import/load/unload state.

RULE
Route Settings actions through application/runtime boundaries.

VERIFY
PR #58 extends Settings with real local model capabilities.

STATUS: CONFIRMED

SOURCE
PR #58

## G-084 — Remote provider isolation

ID: g066-provider-isolation

PURPOSE
Prove the remote provider path independently from local inference.

WHEN
When validating provider execution.

RULE
Keep provider verification separate so local-model success cannot mask remote-provider defects.

VERIFY
PR #66 is a parallel real provider vertical slice.

STATUS: CONFIRMED

SOURCE
PR #66

## G-085 — UI/backend separation

ID: g069-ui-backend-separation

PURPOSE
Keep Agent UI presentation separate from backend execution infrastructure.

WHEN
When building the native Agent surface.

RULE
UI consumes application boundaries; it does not own provider or runtime execution.

VERIFY
PR #69 establishes the Agent-native UI foundation.

STATUS: CONFIRMED

SOURCE
PR #69

## G-086 — Composition-owned execution

ID: g071-composition-owned-execution

PURPOSE
Make Composition the execution entry point for UI-triggered Agent tasks.

WHEN
When a user action starts an Agent task.

RULE
The UI initiates intent; Composition owns orchestration wiring.

VERIFY
PR #71 routes Agent task execution through Composition.

STATUS: CONFIRMED

SOURCE
PR #71

## G-087 — Invalid lifecycle command blocked

ID: g072-invalid-lifecycle-block

PURPOSE
Do not execute runtime commands from invalid lifecycle states.

WHEN
When a Settings action is issued outside the allowed lifecycle.

RULE
Reject or gate the command before reaching runtime execution.

VERIFY
PR #72 gates runtime commands by lifecycle.

STATUS: CONFIRMED

SOURCE
PR #72

## G-088 — Artifact/runtime separation

ID: g078-artifact-separation

PURPOSE
Keep IPA artifact verification separate from runtime feature verification.

WHEN
When evaluating a release artifact.

RULE
A valid artifact does not prove runtime correctness, and runtime correctness does not prove artifact validity.

VERIFY
PR #78 is dedicated to IPA pre-release verification.

STATUS: CONFIRMED

SOURCE
PR #78

## G-089 — Authoritative execution callbacks

ID: g079-authoritative-callbacks

PURPOSE
Use existing execution callbacks as the source of UI progress truth.

WHEN
When displaying reasoning/action/observation/evaluation progress.

RULE
Do not create a parallel progress state machine in the UI.

VERIFY
PR #79 adds live progress and result from Agent execution.

STATUS: CONFIRMED

SOURCE
PR #79

## G-090 — No direct provider access from UI

ID: g081-no-direct-provider-ui

PURPOSE
Prevent the UI from directly accessing provider/storage/native inference infrastructure.

WHEN
When implementing Agent-first UI.

RULE
Use application/runtime boundaries for infrastructure access.

VERIFY
PR #81 explicitly forbids direct llama.cpp/provider/storage access from UI.

STATUS: CONFIRMED

SOURCE
PR #81

## G-091 — Agent-first presentation

ID: g081-progressive-agent-presentation

PURPOSE
Present tasks and outcomes rather than permanent infrastructure milestones.

WHEN
When the backend is operational but the UX is infrastructure-oriented.

RULE
Keep technical details progressively disclosed instead of making them the primary Agent surface.

VERIFY
PR #81 establishes the native Agent experience.

STATUS: CONFIRMED

SOURCE
PR #81

## G-092 — Structural-only migration

ID: g086-structural-only-migration

PURPOSE
Separate physical source migration from behavior redesign.

WHEN
When consolidating legacy repository layout.

RULE
Move ownership first; change behavior in a separate task.

VERIFY
PR #86 defines canonical layer consolidation.

STATUS: CONFIRMED

SOURCE
PR #86

## G-093 — Current-reality documentation

ID: g087-current-reality

PURPOSE
Document what is actually implemented, not what the target architecture intends.

WHEN
When updating architecture documentation after migration.

RULE
Base architectural claims on verified repository evidence.

VERIFY
PR #87 establishes the executable architecture contract.

STATUS: CONFIRMED

SOURCE
PR #87

## G-094 — Append-failure regression

ID: g088-append-failure-regression

PURPOSE
Test the failure case where an authoritative event append fails.

WHEN
When a terminal state transition depends on event persistence.

RULE
The regression must prove state is not committed without its event.

VERIFY
PR #88 adds runtime state/event atomicity regression coverage.

STATUS: CONFIRMED

SOURCE
PR #88

## G-095 — Kernel migration gate

ID: g089-migration-gate

PURPOSE
Stop the next migration group until the current Kernel migration is green and audited.

WHEN
When executing sequential architecture migrations.

RULE
Use CI/build/test evidence as the gate between migration groups.

VERIFY
PR #89 defines the migration scope and validation gate.

STATUS: CONFIRMED

SOURCE
PR #89

## G-096 — Lowest-layer contract ownership

ID: g090-lowest-layer-ownership

PURPOSE
Place stable foundational contracts at the lowest canonical layer that owns them.

WHEN
When a contract has no higher-layer semantics.

RULE
Move ownership downward without redesigning consumers.

VERIFY
PR #90 migrates Foundation and event contracts toward Kernel.

STATUS: CONFIRMED

SOURCE
PR #90

## G-097 — Ownership migration without behavior rewrite

ID: g091-ownership-not-behavior

PURPOSE
Change physical ownership without changing product behavior in the same migration.

WHEN
When moving Cognition and Policy into Runtime.

RULE
Keep the migration narrow and behavior-preserving.

VERIFY
PR #91 records the Cognition/Policy ownership migration.

STATUS: CONFIRMED

SOURCE
PR #91

## G-098 — Durable lessons

ID: g092-durable-lessons

PURPOSE
Persist only reusable evidence-backed lessons.

WHEN
When an Agent discovers a rule worth reusing.

RULE
Do not turn lessons into a volatile session diary.

VERIFY
PR #92 formalizes the compact Markdown Agent protocol.

STATUS: CONFIRMED

SOURCE
PR #92

## G-099 — CI integrity assertions

ID: g093-integrity-assertions

PURPOSE
Preserve existing test and integrity assertions when consolidating CI.

WHEN
When removing duplicate CI notifications.

RULE
Notification simplification must not reduce verification coverage.

VERIFY
PR #93 explicitly preserves assertions.

STATUS: CONFIRMED

SOURCE
PR #93

## G-100 — Behavior-preserving capabilities migration

ID: g094-behavior-preserving-capabilities

PURPOSE
Migrate capability paths without rewriting their behavior.

WHEN
When moving Modules, Skills and Tools into canonical Capabilities.

RULE
Treat the migration as physical structure work first.

VERIFY
PR #94 scopes the Capabilities migration as a canonical-layout change.

STATUS: CONFIRMED

SOURCE
PR #94

## G-101 — Unresolved disposition

ID: g026-unresolved-disposition

PURPOSE
Represent unresolved evidence explicitly during recovery.

WHEN
When evidence cannot determine whether an execution happened.

RULE
Preserve unresolved status instead of forcing a binary result.

VERIFY
PR #26 defines evidence-resolution semantics.

STATUS: CONFIRMED

SOURCE
PR #26

## G-102 — Runtime state authority

ID: g027-runtime-state-authority

PURPOSE
Keep AgentRuntime as the sole state and goal authority.

WHEN
When stores and recovery mechanisms coordinate with runtime state.

RULE
Supporting stores must not become competing state authorities.

VERIFY
PR #27 establishes durable run lifecycle with AgentRuntime authority.

STATUS: CONFIRMED

SOURCE
PR #27

## G-103 — Stable WAL replay

ID: g029-wal-replay

PURPOSE
Replay durable events using stable event identity.

WHEN
When recovering after a crash or interrupted execution.

RULE
Idempotent replay must preserve EventID identity.

VERIFY
PR #29 repairs WAL replay and recovery safety gaps.

STATUS: CONFIRMED

SOURCE
PR #29

## G-104 — Mutation evidence

ID: g031-mutation-evidence

PURPOSE
Persist evidence needed to reconcile whether a mutation occurred across a crash boundary.

WHEN
When execution crosses a durability boundary.

RULE
Use evidence rather than executor return status alone.

VERIFY
PR #31 closes execution-truth gaps with mutation and crash-window tests.

STATUS: CONFIRMED

SOURCE
PR #31

## G-105 — Narrow product boundaries

ID: g032-narrow-product-boundaries

PURPOSE
Expose narrow application boundaries for session, local model, device capability and persistence.

WHEN
When connecting iOS product code to infrastructure.

RULE
Compose infrastructure through explicit product boundaries.

VERIFY
PR #32 establishes the M8 product architecture foundation.

STATUS: CONFIRMED

SOURCE
PR #32

## G-106 — Freeze contracts before runtime

ID: g024-freeze-before-build

PURPOSE
Freeze durable lifecycle contracts before implementing runtime behavior.

WHEN
When a milestone introduces durable execution semantics.

RULE
Resolve architecture and evidence semantics before implementation.

VERIFY
PR #24 freezes the M7.0 architecture specification.

STATUS: CONFIRMED

SOURCE
PR #24

## G-107 — Proven component reuse

ID: g047-proven-particle-reuse

PURPOSE
Prefer reuse of already-proven runtime components during local-model evolution.

WHEN
When extending a runtime with known working pieces.

RULE
Audit and reuse existing proven components before creating duplicates.

VERIFY
PR #47 explicitly performs a proven runtime particle reuse audit.

STATUS: CONFIRMED

SOURCE
PR #47

## G-108 — Fresh CI action runtime

ID: g062-action-runtime-freshness

PURPOSE
Keep action runtime versions aligned with the supported Node version.

WHEN
When GitHub Actions deprecates an action runtime.

RULE
Upgrade action versions as a bounded CI maintenance task.

VERIFY
PR #62 upgrades GitHub Actions to Node 24.

STATUS: CONFIRMED

SOURCE
PR #62

## G-109 — Picker handoff contract

ID: g067-picker-handoff

PURPOSE
Treat document-picker selection delivery as a boundary contract.

WHEN
When a system document is selected for import.

RULE
Verify the URL reaches the application boundary before model processing.

VERIFY
PR #67 repairs the GGUF document picker boundary.

STATUS: CONFIRMED

SOURCE
PR #67

## G-110 — Import boundary probe

ID: g068-import-probe

PURPOSE
Instrument uncertain file-import handoff before changing downstream processing.

WHEN
When Files shows a document but the app receives nothing.

RULE
Prove the handoff boundary first.

VERIFY
PR #68 adds a universal import handoff probe.

STATUS: CONFIRMED

SOURCE
PR #68

## G-111 — Runtime control surface

ID: g070-runtime-control-surface

PURPOSE
Expose runtime controls through the product surface without moving runtime ownership.

WHEN
When users need load/unload or execution controls.

RULE
Controls invoke existing application boundaries.

VERIFY
PR #70 expands Agent runtime controls in Settings.

STATUS: CONFIRMED

SOURCE
PR #70

## G-112 — Native UI scope

ID: g075-native-ui-scope

PURPOSE
Keep a UI milestone from silently becoming a backend rewrite.

WHEN
When building the first native Agent UI.

RULE
Limit the UI task to presentation and application-boundary integration.

VERIFY
PR #75 explicitly excludes backend/runtime and provider redesign.

STATUS: CONFIRMED

SOURCE
PR #75

## G-113 — Infrastructure hidden by default

ID: g081-infrastructure-hidden

PURPOSE
Do not make kernel/provider/storage details the default Agent UX.

WHEN
When exposing a production-like Agent experience.

RULE
Show task intent and result first; reveal infrastructure only when useful.

VERIFY
PR #81 defines the native Agent experience with progressive disclosure.

STATUS: CONFIRMED

SOURCE
PR #81

## G-114 — Green baseline before architecture docs

ID: g087-green-baseline

PURPOSE
Use a green verification baseline before freezing architecture documentation.

WHEN
When a migration has just completed.

RULE
Architecture claims should be anchored to a verified baseline commit.

VERIFY
PR #87 documents a verified green baseline.

STATUS: CONFIRMED

SOURCE
PR #87

## G-115 — Terminal transition atomicity

ID: g088-terminal-atomicity

PURPOSE
Do not commit a terminal runtime state if its authoritative event cannot be appended.

WHEN
When terminal state publication depends on event storage.

RULE
State and event publication form one semantic boundary.

VERIFY
PR #88 fixes runtime state/event atomicity.

STATUS: CONFIRMED

SOURCE
PR #88

## G-116 — Human-readable canonical persistence

ID: g092-human-readable-canonical

PURPOSE
Keep Markdown human-readable while adding durable Agent knowledge.

WHEN
When building the Personal Agent OS knowledge plane.

RULE
Future tooling must not replace Markdown as the canonical human-readable surface.

VERIFY
PR #92 formalizes Markdown Agent state.

STATUS: CONFIRMED

SOURCE
PR #92

## G-117 — Apple IPA gate

ID: g094-apple-ipa-gate

PURPOSE
Include Apple build and IPA evidence in a capability migration gate.

WHEN
When a capability migration affects the iOS product.

RULE
Linux tests alone are insufficient for an Apple artifact claim.

VERIFY
PR #94 reports Apple/IPA verification with the migration.

STATUS: CONFIRMED

SOURCE
PR #94


## Corpus note

This 100-grain corpus is an evidence-backed expansion of the real repository history. The additional grains are semantic decompositions of concrete historical PR work, not invented product assumptions. No parser, index, database, or retrieval implementation is introduced by this task. The corpus remains Markdown-only so Agent semantic retrieval and composition can be tested directly.
