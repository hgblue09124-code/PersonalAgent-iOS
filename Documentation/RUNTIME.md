# Runtime Contract

Runtime owns the agent execution lifecycle: receiving work, planning where required, invoking capabilities/providers through contracts, observing outcomes, verifying results and producing the authoritative result.

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
