# Provider Architecture

```text
Provider contract
      ↓
Provider selection / routing
      ↓
Concrete adapter
      ↓
Vendor / network / native runtime
```

## Rules

- Contracts expose application concepts, not vendor SDK types.
- Remote and local providers are peers where semantics permit.
- Concrete implementations stay inside provider adapters.
- Local llama.cpp is an implementation detail of the local provider boundary.
- Local failure must not silently become remote execution unless explicitly contracted.
- Credentials do not belong in agent state.
- Network availability is explicit state/capability.

## Verification

Check contract compatibility, routing, fail-closed errors, credential isolation, package tests, native build and physical-device behavior when affected.
