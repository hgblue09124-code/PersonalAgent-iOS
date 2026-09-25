# Testing and Green Gates

## Verification hierarchy

1. **Static architecture:** imports, target boundaries, forbidden dependencies and obsolete paths.
2. **Package tests:** complete Swift package test suite for the affected state.
3. **Apple native build:** supported iOS build.
4. **Device validation:** physical target device when behavior is device-specific.
5. **Behavioral evidence:** actual observable behavior for runtime/provider/model changes.

A slice is green only when every gate relevant to its scope passes.

## Regression rule

Every confirmed bug gets a reproducer, regression coverage where practical, the smallest fix, rerun of the affected gate and full compatibility verification.

Never weaken tests, accept ambiguous output as success, replace real behavior with fake success or skip architecture checks because compilation passes.
