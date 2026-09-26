# native-llama-runtime
ID
native-llama-runtime

PURPOSE
Replace simulated local inference with the real native runtime while preserving vendor isolation.

WHEN
A local inference prototype needs production-native execution.

RULE
Integrate the official llama.cpp native target behind PAProvidersLocal; keep single-resident-model coordination and deterministic native resource release.

VERIFY
PR #36 explicitly wires native llama C APIs and preserves the provider boundary.

STATUS
CONFIRMED

SOURCE
PR #36 — official native llama.cpp runtime repair