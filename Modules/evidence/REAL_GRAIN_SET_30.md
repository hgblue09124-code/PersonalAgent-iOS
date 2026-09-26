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
