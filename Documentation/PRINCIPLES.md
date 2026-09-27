# Architecture Principles

1. **Boundary before implementation.** Define responsibility and contract before moving or creating implementation code.
2. **One responsibility, one owner.** Avoid duplicate coordinators, shadow state and parallel abstractions.
3. **Contracts are smaller than implementations.** Expose only what callers need.
4. **Composition wires; it does not reason.**
5. **Kernel stays vendor-neutral.**
6. **Runtime does not become persistence.**
7. **Memory semantics are not storage mechanics.**
8. **Fail closed.** Unknown, malformed, ambiguous or unverifiable states do not become success.
9. **Verified success is independent success.** Execution success alone is insufficient.
10. **No speculative refactor.** Move code only for a confirmed responsibility or dependency problem.
11. **Preserve green.** Every migration slice has a known green start and green exit gate.
12. **Physical evidence for device behavior.** Compilation and tests do not replace physical iPhone validation.
