# AGENTS.md

## Scope & Operating Instructions for Jules

### Primary Scope
- This repository (`PersonalAgent-iOS`) contains a Swift Package Manager (`Package.swift`) target encompassing core architecture, contracts, kernel, provider runtimes, module runtimes, storage, memory OS, and tests (`Sources/`, `Tests/`).
- On Linux build environments (e.g. CI / Linux VMs), execution and testing are restricted to the Swift Package Manager targets (`Package.swift`).

### Rules & Instructions
1. **One Task = One Logical Commit**: Each Agent On task must produce at most one logical commit. Do not create separate commits for memory checkpoints, audit notes, handoff updates, CI notifications, or intermediate repair steps. Bundle all changes belonging to the same task into that single commit. Do not use automated workflows to create follow-up commits.
2. **Target Boundary**: Do NOT touch, open, or attempt to resolve `PersonalAgent.xcodeproj` or anything under `App/` on Linux VMs where Xcode is not installed.
3. **Package Validation**: All core logic, contracts, runtimes, and test suites must compile and pass cleanly via Swift Package Manager (`swift test --disable-sandbox` or `docker run --rm -v $(pwd):/src -w /src swift:6.3.2 swift test --disable-sandbox`).
4. **Environment Setup**: If `swift` binary is not present in PATH on Linux VM, execute SPM tests via the official `swift:6.3.2` Docker container:
   `docker run --rm -v $(pwd):/src -w /src swift:6.3.2 swift test --disable-sandbox`

### Durable Agent Memory
- Before non-trivial work, read `Documentation/LESSONS.md` after this file.
- `WORK_LOG.md` records execution history; `LESSONS.md` stores only reusable, evidence-backed lessons.
- Record a lesson only when the cause is supported by concrete code, test, or CI evidence. Use `OBSERVED` until verified; use `CONFIRMED` after verification.
- Promote a lesson to this file or `Documentation/ARCHITECTURE.md` only after independent repetition or when it is architecture-critical.
- Never use durable memory as a volatile session diary. Do not create separate memory commits.

### Personal Agent OS Markdown
- `Documentation/PERSONAL_AGENT_OS_MARKDOWN.md` is the product foundation for the Markdown-native Personal OS.
- Markdown is persistent cognitive state, not generated documentation.
- Agent work follows the product loop: **Read → Act → Verify → Learn → Persist**.
- Keep Markdown surfaces complementary: identity, architecture, lessons, audit, handoff, and execution history must not become duplicate diaries.
- Future indexing or retrieval layers must preserve Markdown as the canonical human-readable persistence surface.
