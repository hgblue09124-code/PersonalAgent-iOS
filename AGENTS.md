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
