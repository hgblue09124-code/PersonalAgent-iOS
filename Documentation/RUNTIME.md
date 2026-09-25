# Runtime Contract

## Target responsibility

Runtime owns the agent execution lifecycle: receiving work, planning where required, invoking capabilities/providers through contracts, observing outcomes, verifying results and producing the authoritative result.

## Current implementation

At the green M8 baseline, the main `AgentRuntime` implementation is still part of the `PAKernel` SwiftPM target. The target architecture intends to separate runtime orchestration from the stable Kernel contract/port layer.

Do not move `AgentRuntime` merely to satisfy folder aesthetics. First identify which responsibilities are runtime behavior and which are kernel contracts/invariants, then migrate incrementally.

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
