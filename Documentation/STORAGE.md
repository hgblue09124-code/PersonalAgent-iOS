# Storage Architecture

Storage owns durable representation and persistence mechanics.

Typical domains:

- Models
- Skills
- Memory persistence
- Configuration
- Cache
- Sync

## Rules

- APIs expose domain-safe contracts.
- Physical implementation details remain below the storage boundary.
- Runtime does not manipulate persistence directly.
- Failures are explicit.
- Cache is not authoritative unless the contract says so.
- Secrets are not ordinary agent state.

A write is successful only when the storage contract's durability guarantee is satisfied.
