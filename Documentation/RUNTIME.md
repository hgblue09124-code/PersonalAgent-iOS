# Runtime Contract

## Target responsibility

Runtime owns the agent execution lifecycle: receiving work, planning where required, invoking capabilities/providers through contracts, observing outcomes, verifying results and producing the authoritative result.

## Current implementation

`AgentRuntime` and `AgentSession` are implemented in the `PARuntime` SwiftPM target under `Sources/Runtime`. Composition constructs them and owns dependency wiring; Kernel remains the stable contract/state/port layer.

The runtime boundary is explicit in the package graph:

```text
App
  ↓
Composition
  ↓
PARuntime
  ↓
PAKernel
```

`PARuntime` may depend on the contracts it orchestrates, but application code must enter runtime through the session/runtime boundary rather than duplicating lifecycle or execution logic.

## Lifecycle

```text
Request → Planning → Action → Observation → Verification → Result
```

Not every request requires every stage, but their meanings remain distinct.

## Invariants

- Execution success is not verification success.
- Verification uses evidence appropriate to the action.
- Unknown or malformed state fails closed.
- Runtime state does not secretly become persistence.
- Provider selection is routing, not vendor implementation.
- User-facing trace describes observable execution stages, not private chain-of-thought.

## Change gate

Prove lifecycle behavior, error propagation, verification behavior, cancellation/lifecycle safety where relevant, regression coverage and architecture compliance.
