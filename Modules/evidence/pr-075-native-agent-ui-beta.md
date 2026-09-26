# native-agent-ui-beta
ID
native-agent-ui-beta

PURPOSE
Establish an Agent-first native UI without redesigning backend/runtime ownership.

WHEN
Building the first coherent iOS Agent experience.

RULE
Use native SwiftUI presentation, progressive disclosure, and task-first interaction while preserving existing application boundaries.

VERIFY
PR #75 explicitly excludes backend/runtime, llama.cpp/provider, and security-hardening redesign from the beta slice.

STATUS
CONFIRMED

SOURCE
PR #75 — BIG UI native agent beta foundation