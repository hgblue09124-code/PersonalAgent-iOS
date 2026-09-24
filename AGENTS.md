# AGENTS.md — PersonalAgent-iOS Agent Operating Contract

## Mission

Work on the smallest correct change required by the task.

Optimize for:
1. correctness
2. architectural alignment
3. minimal change
4. fast verification
5. low token/context usage

Do not expand scope unless a contract violation requires it.

## Execution Protocol

For every task:
1. Read this file.
2. Inspect only files directly relevant to the task.
3. Identify the authoritative owner, contract, and exact acceptance condition.
4. Make the smallest implementation change.
5. Add/update the smallest regression test.
6. Run the narrowest sufficient verification.
7. Stop when acceptance criteria are satisfied.
8. Report changed files, verification, behavior, limitations, and next action.

Do not perform a broad architecture audit unless CI/build fails, runtime behavior contradicts a contract, a new architectural boundary is required, or the task explicitly requests an audit.

## Authority

- UI: render state and collect intent; never invent runtime truth.
- App/Application: translate UI intent into application operations.
- Composition: wire concrete implementations; no business logic.
- Agent Runtime: authoritative goal execution state, lifecycle, and execution result.
- Orchestrator: coordinate cognition/execution; never create a second runtime state machine.
- ExecutionBoundary: capability, policy, lease, execution, and evidence boundary.
- Provider: provider/model interaction.
- Local Model Runtime: active-model loading and native inference.
- Storage: persistence and model files.
- Events/Evidence: provenance and verification evidence.

One authoritative owner per concern. Never duplicate authoritative state.

## Canonical Agent Path

User Task → Goal → Orchestrator → Reason → Action Proposal → ExecutionBoundary → Action → Observation → Verification → Evaluation → Result

Submitting a Goal is NOT executing a Goal.

LLM text is NOT an executed action.

Action success is NOT verification success.

No verification evidence means NOT VERIFIED and NOT PASS.

Malformed, ambiguous, empty, or missing evidence fails closed.

## Local Model Path

Active Model → Local Model Runtime Coordinator → Local Model Engine → Local Provider Adapter → LLMProvider → Agent Reasoner

UI must never call llama.cpp directly.

Agent code depends on model/provider contracts, not concrete llama.cpp APIs.

If an active real model exists, never silently replace its failure with fake success.

## Lifecycle

Lifecycle is authoritative. Do not weaken transitions to make UI commands work.

Invalid transitions remain invalid. Terminal states remain terminal unless an explicit restart contract exists.

Never add `running → start` merely to make repeated Start commands work.

Fix the caller/UI instead.

## Failure Contract

Fail closed for:
- missing active model or descriptor
- model load/inference failure
- empty LLM output
- malformed reasoning output
- unknown action/tool
- action failure
- missing observation/evidence
- failed verification
- exceeded execution limit
- terminal runtime
- inconsistent model identity

Never convert an error into fake success.

## Scope Discipline

Prefer: one contract → one implementation → one regression test.

Avoid:
- broad refactors
- speculative abstractions
- duplicate registries/runtimes/state machines
- new frameworks
- unrelated cleanup
- UI redesign during backend work
- backend redesign during UI work

Reuse existing seams when they satisfy the task.

## Verification

Use the cheapest sufficient verification:
1. compiler
2. focused unit test
3. focused integration test
4. relevant CI
5. physical device test
6. deep audit only when necessary

Do not spend tokens re-proving established behavior.

Do not claim device behavior from unit tests.

## Development Mode

Optimize for iteration speed. Keep runtime contracts intact.

Final device/release evidence is a milestone gate, not a blocker for every development slice unless explicitly required.

## Stop Condition

Stop when requested behavior works, the contract is preserved, focused verification passes, and no unrelated regression is introduced.

## Final Report

STATUS: PASS | BLOCKED

CHANGED:
- file

VERIFY:
- test/build
- result

BEHAVIOR:
- one sentence

LIMITATION:
- only if relevant

NEXT:
- only if required
