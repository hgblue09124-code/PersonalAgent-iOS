# Architecture Baseline

## Status

**Baseline:** M8 Architecture Baseline — Verified Green

**Baseline source commit:** `9cbd2a0a1c6cd0d76523cbf88dbecbfe6ec121cf`

**Baseline branch:** `baseline/architecture-m8`

This document freezes the verified architecture/integration state represented by the baseline source commit. It is a reference point for subsequent hardening work.

## Verified scope

- M0 contract foundation
- M1 Kernel + Runtime
- M2 Provider contracts and provider vertical slice
- M3 Skills + Tools
- M4 Storage + Memory
- M6 Cognition + Agency loop
- M7 Runtime lifecycle/recovery and failure-window regression
- M8 architecture/product foundation
- M8.1 real native Llama.cpp local inference
- M8.2 active local-model binding
- M9 parallel provider vertical slice

## Architecture invariants

- GREEN means the verified tests/contracts/dependency declarations passed at the baseline; it does not mean architectural perfection.
- `PAKernel` must not import concrete vendor providers or UI frameworks.
- Runtime remains separated from the Kernel source boundary.
- Composition owns construction and wiring.
- Companion repositories are not runtime dependencies.
- Architecture declarations must remain aligned with the actual SwiftPM dependency graph.
- Subsequent hardening must preserve baseline behavior unless an intentional contract change is documented and verified.

## Known audit targets

These were identified before the baseline and are **not** treated as confirmed defects solely by being listed here:

1. Kernel coordination responsibility and `KernelCoordinationBoundary`.
2. Composition concentration, especially `LocalModelRuntimeCoordinator`.
3. Provider contract/routing/vendor-adapter separation.
4. Memory semantics versus physical Storage implementation.
5. Dependency direction and whether Kernel/Runtime currently own more domain dependencies than necessary.

## Baseline rule

Any future architecture-hardening change should be evaluated against this baseline:

`baseline/architecture-m8` → audit → minimal change → regression verification → new green point.

Do not silently redefine the baseline to accommodate a failing change.
