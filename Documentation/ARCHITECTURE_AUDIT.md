# Architecture Audit Record

## Baseline

- Verified source baseline: `9cbd2a0a1c6cd0d76523cbf88dbecbfe6ec121cf`
- Audit branch: `baseline/architecture-m8`
- This report records findings before any architecture refactor.
- The baseline source commit is the known green point; later documentation commits are not considered green until CI verifies them.

## Audit #1 — Dependency Direction

### Confirmed

- No SwiftPM dependency cycle was observed.
- `PAKernel` does not import concrete vendor provider implementations.
- `PAKernel` does not import UI frameworks.
- Runtime source has been separated from the Kernel source boundary.
- Composition remains the construction/wiring layer.

### Finding

**🟠 Confirmed architecture coupling:** `PARuntime` directly depends on multiple capability/domain targets in addition to `PAKernel`: Providers, Modules, Memory, Cognition, Policy and Agency.

`PAKernel` is also broad, depending on Policy, Agency, Cognition, Providers, Modules and Memory.

This is not a SwiftPM cycle, but it makes the Kernel/Runtime boundary heavier than a minimal orchestration contract.

## Audit #2 — Kernel Contract Ownership

### Confirmed

`Sources/Core/Agent/KernelContracts.swift` defines core concepts such as identity, goal and lifecycle state, but also imports Policy, Agency, Cognition, Observability and Events.

`Sources/Core/Agent/KernelCoordination.swift` defines `KernelCoordinationBoundary` containing optional coordination slots for:

- Policy
- Planner
- Executor
- Agency
- Provider
- Modules
- Memory

This makes the Kernel a broad coordination hub rather than a narrowly defined core contract.

### Classification

**🟠 Architecture coupling:** Kernel contract surface is broader than necessary.

**🟡 Architecture smell:** `KernelCoordinationBoundary` may be a transitional M6/M7 integration seam, but its final ownership should be verified before refactoring.

No production bug has been established from this finding.

## Other Observations

### Memory

`PAMemory` depends on `PAStorage`, and memory records currently use the storage abstraction.

**🟡 Architecture smell, not confirmed defect.**

The current design is functional, but long-term separation between memory semantics and physical persistence may provide a cleaner boundary.

### Composition

`M8CompositionRoot` contains substantial construction and lifecycle wiring.

**🟡 Architecture smell, not confirmed defect.**

It is currently directionally correct for Composition to own concrete wiring. Splitting it should wait until natural ownership seams are demonstrated.

## Rules for Follow-up

1. Do not refactor based only on smells.
2. Continue evidence-driven audits from the verified baseline.
3. Classify each finding as confirmed defect/coupling, architecture smell, or intentional/acceptable.
4. If a fix is justified: inspect → confirm → minimal fix → regression test → full CI → audit → new green point.
5. Preserve baseline behavior unless an intentional contract change is explicitly documented.

## Next Audit

**Audit #3 — Contract Surface**

Inspect actual contracts for Cognition, Agency, Providers, Modules and Memory to determine which dependencies are genuinely required by Kernel and which are merely pulled upward by coordination design.
