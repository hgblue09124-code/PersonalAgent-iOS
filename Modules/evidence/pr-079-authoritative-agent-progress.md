# authoritative-agent-progress
ID
authoritative-agent-progress

PURPOSE
Show real Agent execution progress without introducing a second runtime state machine.

WHEN
Local GGUF execution is working but Chat lacks visible execution narrative/result.

RULE
Use authoritative M6Orchestrator callbacks for reasoning/action/observation/evaluation progress and final result; keep lifecycle and local-model ownership unchanged.

VERIFY
PR #79 explicitly rejects a second runtime/state machine and reserves token streaming for a later slice.

STATUS
CONFIRMED

SOURCE
PR #79 — live Agent execution progress and result