# Living Cognitive Data Ocean

`Modules/` is the product data plane for Personal Agent OS Markdown.

It is separate from `Sources/Capabilities/Modules`:
- `Sources/Capabilities/Modules` = executable module runtime contracts and implementations.
- `Modules/` = persistent human-readable cognitive grains that the Agent can discover, verify, and compose.

## Core model

Sea of Chaos
    ↓ discover / observe
candidate text
    ↓ evaluate
Living Grain
    ↓ select + compose
Cognitive Module
    ↓
Agent action
    ↓ verify
new evidence
    ↓
new / refined grain

Live means usable now, not realtime. A living grain has enough meaning, boundary, status, and evidence for an Agent to use it without re-reading the whole Ocean.

## Minimum Grain Contract

A grain is intentionally soft Markdown. It normally exposes:
- ID
- PURPOSE
- WHEN
- RULE or KNOWLEDGE
- VERIFY
- STATUS
- SOURCE

Fields may be omitted when they do not apply. The boundary and evidence are mandatory in meaning, not necessarily as rigid syntax.

Lifecycle: OBSERVED → CONFIRMED → PROMOTED

Only confirmed or promoted grains are eligible for normal reuse. Observed grains remain candidate knowledge until independently verified.

## Composition

A Module is a composed capability, not a folder.

The Agent should:
1. discover candidate grains;
2. select only relevant grains;
3. compose the smallest useful module;
4. act;
5. verify independently;
6. persist the resulting evidence or lesson.

Do not build a parser, database, or retrieval service before real grain usage demonstrates a concrete need. Markdown remains the canonical human-readable persistence layer.