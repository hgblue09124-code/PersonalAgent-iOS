# Python Agent Runtime — planning core

This package is the first incremental Python-side runtime component for PersonalAgent-iOS.

## Boundary

- Python classifies intent and emits typed plans/proposals.
- Swift remains authoritative for iOS UI, user consent, Settings capabilities, policy evaluation, tool execution, and result verification.
- Serialized plans use `schema_version: 1`; the embedded Swift bridge rejects incompatible or self-authorized envelopes.
- A plan is never proof of execution. AgentPlan.is_executable is always false.
- Unknown, incomplete, or out-of-scope requests must not become tool proposals.

## Current scope

The deterministic planner handles generic chat and a narrow create-file intent in Vietnamese/English. It only recognizes explicit paths under workspace/ and content supplied after nội dung:, noi dung:, or content:. Ambiguous requests return clarification rather than guessing.

The source package lives in `app/personal_agent_runtime` and is bundled into the iOS app. `PAPythonRuntimeBridge` initializes embedded CPython 3.15.2 and invokes `plan_request`; `EmbeddedPythonAgentRuntime` serializes calls. The runtime is a planner only: Swift validates its versioned JSON proposal and owns all scope, policy, approval, execution, and read-back behavior.

## Build and run on iOS

The Apple build workflow downloads the official CPython 3.15.2 iOS XCFramework from python.org, verifies its pinned SHA-256, then Xcode embeds it and runs the upstream `install_python` packaging step. For a local Xcode build, run:

    bash Scripts/prepare_python_ios_runtime.sh

The XCFramework is intentionally ignored by Git and is not committed to this repository.

## Run tests

    PYTHONPATH=app python3 -m unittest discover -s AgentRuntimePython/tests -v
    python3 -m compileall -q app/personal_agent_runtime
