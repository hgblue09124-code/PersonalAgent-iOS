# Agent Loop ↔ Skill Integration Contract

Status: proposed normative design. This document is not evidence that the integration is implemented.

## 1. Verified current state

- `M6CompositionRoot` is the canonical M6 composition boundary and depends on both `PARuntime` and `PASkills`.
- `M6Orchestrator` owns the bounded cognition/agency loop, policy decision, approval request, execution observations, evaluation, reflection, and authoritative goal transition.
- `ContextBundle` already carries `skillIDs`, but `DefaultContextAssembler` returns an empty list.
- `DefaultPlanner` currently produces `PlanStep(skillID: nil)`.
- `ActionProposal` currently carries `toolID` but no Skill identity, so the plan's `skillID` has no execution route.
- `LLMReasoner` sends the raw user input to the provider; it does not add selected Skill instructions or use `context.skillIDs`.
- `PASkills` already contains `SkillMarkdownParser`, `FileSkillStore`, `SkillRuntime`, `SkillExecutorRegistry`, and `SkillAgentOrchestrator`. These are not wired into the canonical M6 path.
- `SkillAgentOrchestrator` selects a Skill, executes it, and verifies output, but its current API has no `ApprovalGate` parameter. `SkillRuntime` rejects a policy decision that requires approval. It must not be treated as a drop-in approval-aware M6 action runner.
- The Skill runtime resolves only registered/built-in executors and allowlisted module adapters. Skill Markdown must remain declarative; a metadata executor name must never instantiate arbitrary code.

These are source-level findings. They do not establish that every other Skill or runtime path is broken.

## 2. Dependency rule

Keep the dependency direction:

```text
PARuntime defines neutral contracts
        ↑ implemented/adapted by
PAComposition (depends on PARuntime + PASkills + PAModules)
        ↓ wires
M6Orchestrator + Skill runtime + provider + policy + module runtime
```

`PARuntime` MUST NOT import `PASkills`. Runtime contracts may refer to kernel-owned identifiers and evidence types only. Concrete Skill discovery, Markdown loading, executor selection, and Skill-to-module adaptation belong in Composition or PASkills.

## 3. Canonical flow

```text
User goal
  → Perception / context
  → Discover available Skill manifests
  → Apply Agent allowlist and disabled-state filters
  → Select only a unique, high-confidence match
       ├─ no match / ambiguous → ordinary answer-only reasoning
       └─ selected Skill
            → validate manifest + input contract
            → PlanStep(skillID)
            → ActionProposal(skillID)
            → structural verification
            → policy decision
            → explicit approval if required
            → Skill executor through existing ModuleRuntime boundary
            → independent output verification
            → Observation + provenance
  → Evaluation
  → Reflection
  → authoritative StateUpdate
  → complete / abort / bounded continuation
```

A Skill is a capability, not a prompt suggestion and not a synonym for a Tool. The plan must preserve Skill identity through proposal, authorization, execution, observation, and audit evidence.

## 4. Neutral Runtime contracts

The Runtime-facing contract should be minimal and testable. Exact names may change during implementation, but these semantics are required:

- `SkillSelectionBoundary`: returns zero or one selected `SkillID` from an already validated and scoped set. It must distinguish “no match” from malformed registry/storage failures.
- `SkillExecutionBoundary`: accepts a selected `SkillID`, a typed/serialized input, and an authorization context; returns a receipt containing Skill ID, output, executor identity/version, and verification status.
- `SkillExecutionReceipt`: can only be marked verified after the same resolved executor instance verifies its output.
- `ActionProposal`: carries optional `skillID` independently from `toolID`. A Skill step must not be disguised as a tool by encoding its identity in free-form text.
- `AgentExecutionEvidence`: links goal, plan, action, Skill ID/version, policy decision, execution attempt, output verification, and terminal disposition without recording secrets.

The Composition adapter implements these contracts using PASkills. Do not leak concrete `SkillRuntime` types into PARuntime.

## 5. Selection and fallback rules

1. Filter by the Agent manifest's declared Skill IDs before intent matching.
2. Reject an Agent manifest that declares missing Skills; do not silently widen its scope.
3. Exclude disabled Skills and reject duplicate IDs or malformed manifests.
4. Select only an exact or unique high-confidence match. Equal scores and weak overlap return “no match”.
5. “No match” may use answer-only reasoning; malformed store data, failed validation, scope mismatch, or policy denial must remain explicit errors.
6. The LLM may recommend a Skill, but its text is not authorization. Runtime revalidates the ID against the scoped registry.
7. Never auto-select a Skill merely because it exists or is the first item in a list.

## 6. Authorization and execution

- Verify the proposed Skill ID, manifest version, declared capabilities, input schema identity, output schema identity, and resolved executor before execution.
- Evaluate the required capability at the policy boundary. If approval is required, a missing gate, cancellation, or rejection MUST deny execution.
- The existing `SkillRuntime` policy path rejects `requiresApproval`; the integration must explicitly reconcile approval with the nested `ModuleRuntime` policy. It must not approve at M6 and then accidentally re-evaluate as denied, nor bypass the nested policy with an implicit allow.
- No module or tool execution occurs merely because the model mentions a Skill.
- Only registered executors and explicit allowlisted adapters may run. Markdown fields cannot grant permissions or load code.
- Cancellation is checked before execution and again after a non-cooperative executor returns; late output cannot become a successful observation.
- A successful process exit or non-empty output is not proof of task completion. Require executor verification and, where appropriate, semantic postconditions.

## 7. State and evidence invariants

- A Skill result must flow through the existing M6 Observation → Evaluation → Reflection → StateUpdate sequence.
- The canonical event chain records selection, proposal, policy decision, approval, execution attempt, verification outcome, and final state using the same trace/goal/action identities.
- Missing execution target, malformed input, schema mismatch, policy denial, failed verification, cancellation, or audit persistence failure must never produce a successful terminal state.
- A cycle budget is a hard terminal bound. If the last allowed cycle still says `continue`, convert it to an explicit abort before persisting the final evaluation/state.
- Provider completion, Skill execution, and Skill verification are distinct facts. None implies the next.

## 8. Skill.md lifecycle

```text
create / import / edit
  → parse canonical grammar
  → validate required fields + version + unique identity
  → validate input/output contract identities
  → resolve registered executor (never dynamic code)
  → stage candidate version
  → run executor and verification tests
  → activate candidate
  → retain previous known-good version for rollback
```

All entry points must use the same parser. A failed parse or validation must not overwrite the currently active Skill. Schema identifier matching is contract-identity validation, not full structural JSON Schema validation; structural validation must be a separately tested capability.

## 9. Required regression matrix

| Scenario | Required result |
| --- | --- |
| Unique in-scope built-in Skill | Executes via approved boundary; receipt is verified |
| No matching Skill | Answer-only path remains functional; no Skill execution event |
| Ambiguous match | No arbitrary selection; explicit no-match fallback |
| Skill outside Agent allowlist | Rejected before executor invocation |
| Missing/disabled/duplicate Skill | Fail closed with actionable evidence |
| Malformed Skill.md or input | Rejected before side effects; prior active version retained |
| Input/output contract mismatch | Rejected before execution or verification |
| Unregistered executor / unknown adapter | No dynamic load; execution rejected |
| Policy denial | No executor invocation; no successful observation |
| Approval required, gate absent | Denied |
| Approval required, gate rejects | Denied |
| Approval granted | One coherent authorization path through nested ModuleRuntime |
| Executor returns invalid output | Verification fails; goal cannot complete successfully |
| Cancellation before/after executor | No late success state; cancellation remains visible |
| Provider failure / empty answer | Error is visible; no synthetic successful answer |
| Cycle budget exhausted | Exactly bounded cycles; terminal abort with evidence |
| Audit/event persistence failure | No successful authoritative state transition |
| No-Skill answer-only request | Provider answer preserved as answer, not replaced by “Executed proposal” |

## 10. Implementation order and release gates

1. **Agent loop safety:** provider injection, missing-approval fail-closed, terminal cycle-budget exhaustion, cancellation/error propagation, and audit evidence.
2. **Skill execution seam:** add Runtime-neutral selection/execution contracts and carry `skillID` from context to plan to proposal.
3. **Composition adapter:** construct the Skill store/runtime from the canonical app data directory, register only known executors, and inject adapters without reversing package dependencies.
4. **Authorization reconciliation:** make approval semantics consistent across M6, SkillRuntime, and ModuleRuntime before enabling write/execute Skills.
5. **End-to-end tests:** cover the matrix above with deterministic fake provider, Skill executor, policy, approval gate, and event log.
6. **CI evidence:** task contract + M3 Swift tests + Apple Native Build/Unsigned IPA. Real remote-provider, GGUF, and physical-device behavior remain separate gates.

This design is not “implemented” until the source path, regression tests, changed-file diff, commit SHA, and CI run IDs prove the relevant criteria.
