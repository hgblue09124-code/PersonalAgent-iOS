# Capabilities Architecture

Capabilities are bounded reusable actions or knowledge units exposed to runtime.

## Modules

Modules provide bounded executable capabilities and contracts.

## Skills

Skills package reusable agent knowledge or procedures and may compose capabilities.

## Tools

Tools expose external or privileged operations and are policy-gated.

## Rules

- Capabilities do not own provider internals.
- Tools do not bypass policy.
- Skills do not directly mutate arbitrary infrastructure.
- Modules should be as small as practical while retaining coherent responsibility.
- Capability contracts should be independently testable where practical.
- A new capability domain needs a real ownership boundary; do not create one for naming alone.
