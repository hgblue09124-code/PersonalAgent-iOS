# Living Cognitive Data Ocean

Status: Product architecture established.

Personal Agent OS Markdown is not a documentation archive. It is a persistent, human-readable cognitive data plane in which small, evidence-backed units can remain alive, discoverable, and composable.

## Ocean model

Sea of Chaos → candidate material → evaluate → Living Grain → select + compose → Cognitive Module → Agent action → verify → new evidence → new or refined grain.

Sea of Chaos contains material still being discovered or evaluated. Living Ocean contains grains that have enough boundary, meaning, and evidence to be used directly.

Live does not mean realtime. It means ready-to-use.

## Grain

A cognitive grain is the smallest independently useful unit of knowledge or capability.

A grain is not defined by file size and is not merely a Markdown file. A file is a persistence representation; the grain is the semantic boundary inside that representation.

A grain should answer:
- what is this?
- when is it relevant?
- what may the Agent rely on?
- how is it verified?
- where did it come from?

The minimum contract remains intentionally soft Markdown. Do not force every grain into JSON, YAML, or a rigid schema.

## Lifecycle

OBSERVED → CONFIRMED → PROMOTED

- OBSERVED: candidate information; not trusted for normal reuse.
- CONFIRMED: evidence supports direct reuse.
- PROMOTED: durable knowledge that has earned architectural or repeated-use status.

Promotion must never be speculative.

## Module composition

A Module is a capability boundary assembled from grains.

The Agent retrieves only grains relevant to the current task, composes the smallest useful module, acts, verifies, and persists the resulting learning.

The folder Modules/ is an organization surface. It does not itself define the capability boundary.

## Runtime boundary

Modules/ is the persistent cognitive-data plane.
Sources/Capabilities/Modules is the executable capability runtime.

Markdown does not bypass Kernel, Runtime, Composition, Policy, or other ownership boundaries.

## Evolution path

Markdown grains → observed usage → concrete retrieval need → parser/index → retrieval → Agent composition → semantic memory.

The parser and index are downstream implementation details. Markdown remains the canonical human-readable persistence layer.

## Product invariants

1. A human can understand a living grain without an Agent.
2. An Agent can discover a grain without reading the entire Ocean.
3. Evidence determines trust; prose alone does not.
4. Observed knowledge does not silently become confirmed knowledge.
5. A Module is a capability boundary, not a folder.
6. Markdown does not replace runtime ownership.
7. One logical task remains one logical commit.
