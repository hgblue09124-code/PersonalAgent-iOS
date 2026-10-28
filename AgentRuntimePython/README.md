# Python Agent Runtime — planning core

This package is the first incremental Python-side runtime component for PersonalAgent-iOS.

## Boundary

- Python classifies intent and emits typed plans/proposals.
- Swift remains authoritative for iOS UI, user consent, Settings capabilities, policy evaluation, tool execution, and result verification.
- A plan is never proof of execution. AgentPlan.is_executable is always false.
- Unknown, incomplete, or out-of-scope requests must not become tool proposals.

## Current scope

The deterministic planner handles generic chat and a narrow create-file intent in Vietnamese/English. It only recognizes explicit paths under workspace/ and content supplied after nội dung:, noi dung:, or content:. Ambiguous requests return clarification rather than guessing.

This is not yet connected to the iOS app. The next integration step is a versioned JSON bridge with Swift-owned policy validation; do not embed Python execution into the UI or background lifecycle as part of this package.

## Run tests

    python3 -m unittest discover -s AgentRuntimePython/tests -v
    python3 -m compileall -q AgentRuntimePython/personal_agent_runtime
